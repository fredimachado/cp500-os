using System.CommandLine;
using System.Globalization;
using Cp500Os.C5fs;

namespace Cp500Os.C5fs.Cli;

/// <summary>The c5fs command line. Every mutating command changes the image only by an atomic replace.</summary>
public static class C5fsCli
{
    private const int Failure = 1;

    public static int Run(string[] args, TextWriter output, TextWriter error, TimeProvider? timeProvider = null)
    {
        ArgumentNullException.ThrowIfNull(args);
        RootCommand root = BuildCommands(timeProvider ?? TimeProvider.System);
        return root.Parse(args).Invoke(new InvocationConfiguration
        {
            Output = output,
            Error = error,
            EnableDefaultExceptionHandler = false,
        });
    }

    private static RootCommand BuildCommands(TimeProvider time)
    {
        Argument<string> image = new("image") { Description = "Raw floppy image file" };

        Option<int> size = new("--size") { Description = "Image size in KiB", DefaultValueFactory = _ => 360 };
        size.AcceptOnlyFromAmong("180", "360");
        Option<string?> label = new("--label") { Description = "Volume label, up to 16 characters" };
        Option<string?> boot = new("--boot") { Description = "Boot sector file, at most 256 bytes" };
        Command format = new("format", "Create an empty C5FS image") { image, size, label, boot };
        format.SetAction(Guarded(parse =>
        {
            byte[]? bootCode = ReadOptionalFile(parse.GetValue(boot));
            Volume volume = Volume.Format(new FormatOptions
            {
                Geometry = parse.GetValue(size) == 180 ? VolumeGeometry.Floppy180 : VolumeGeometry.Floppy360,
                Label = parse.GetValue(label) ?? "",
                TimeProvider = time,
            });
            if (bootCode is not null)
            {
                volume.InstallBootSector(bootCode);
            }

            string path = parse.GetRequiredValue(image);
            WriteAtomically(path, volume.ToImage());
            Out(parse).WriteLine(Invariant(
                $"{path}: {volume.Geometry.ImageSize / 1024} KiB, {volume.Geometry.BlockCount} blocks, {volume.Geometry.InodeCount} inodes, volume id {volume.Superblock.VolumeId:X8}"));
        }));

        Command info = new("info", "Show the superblock and free space") { image };
        info.SetAction(Guarded(parse => PrintInfo(Out(parse), OpenImage(parse.GetRequiredValue(image), time))));

        Argument<string> listPath = new("path") { Description = "Path inside the image", DefaultValueFactory = _ => "/" };
        Option<bool> longFormat = new("--long", "-l") { Description = "Show type, attributes, inode, size and time" };
        Command ls = new("ls", "List a directory") { image, listPath, longFormat };
        ls.SetAction(Guarded(parse => PrintListing(
            Out(parse), OpenImage(parse.GetRequiredValue(image), time), parse.GetRequiredValue(listPath), parse.GetValue(longFormat))));

        Argument<string> path = new("path") { Description = "Absolute path inside the image" };
        Option<bool> parents = new("--parents", "-p") { Description = "Create missing parents; no error if it exists" };
        Command mkdir = new("mkdir", "Create a directory") { image, path, parents };
        mkdir.SetAction(Guarded(parse => Mutate(
            parse.GetRequiredValue(image), time, volume => volume.CreateDirectory(parse.GetRequiredValue(path), parse.GetValue(parents)))));

        Argument<string> hostFile = new("hostfile") { Description = "File on the host" };
        Command put = new("put", "Copy a host file into the image (create or replace)") { image, hostFile, path };
        put.SetAction(Guarded(parse =>
        {
            byte[] content = File.ReadAllBytes(parse.GetRequiredValue(hostFile));
            Mutate(parse.GetRequiredValue(image), time, volume => volume.WriteFile(parse.GetRequiredValue(path), content));
        }));

        Command get = new("get", "Copy a file out of the image") { image, path, hostFile };
        get.SetAction(Guarded(parse =>
        {
            byte[] content = OpenImage(parse.GetRequiredValue(image), time).ReadFile(parse.GetRequiredValue(path));
            WriteAtomically(parse.GetRequiredValue(hostFile), content);
        }));

        Command rm = new("rm", "Remove a file or an empty directory") { image, path };
        rm.SetAction(Guarded(parse => Mutate(
            parse.GetRequiredValue(image), time, volume => volume.Remove(parse.GetRequiredValue(path)))));

        Option<string?> kernel = new("--kernel") { Description = "Kernel file, installed as /sys/kernel in one contiguous run" };
        Option<string[]> puts = new("--put")
        {
            Description = "Copy a host file to an absolute path in this same session, as host=path. Repeatable.",
            Arity = ArgumentArity.ZeroOrMore,
        };
        Command sys = new("sys", "Install the boot sector and/or the kernel") { image, boot, kernel, puts };
        sys.SetAction(Guarded(parse =>
        {
            byte[]? bootCode = ReadOptionalFile(parse.GetValue(boot));
            byte[]? kernelCode = ReadOptionalFile(parse.GetValue(kernel));
            (string Path, byte[] Content)[] staged = StagePuts(parse.GetValue(puts) ?? []);
            if (bootCode is null && kernelCode is null && staged.Length == 0)
            {
                throw new C5fsException(C5fsError.EINVAL, "sys needs --boot, --kernel or both");
            }

            Volume volume = Mutate(parse.GetRequiredValue(image), time, volume =>
            {
                if (bootCode is not null)
                {
                    volume.InstallBootSector(bootCode);
                }

                if (kernelCode is not null)
                {
                    volume.InstallKernel(kernelCode);
                }

                foreach ((string path, byte[] content) in staged)
                {
                    PutFile(volume, path, content);
                }
            });
            if (volume.Superblock.Kernel is Extent run && kernelCode is not null)
            {
                Out(parse).WriteLine(Invariant($"kernel: blocks {run} ({run.Length} blocks, {kernelCode.Length} bytes)"));
            }
        }));

        Command check = new("check", "Check the image for consistency (exit 1 when problems are found)") { image };
        check.SetAction(parse => Guard(parse, () =>
        {
            IReadOnlyList<string> problems = OpenImage(parse.GetRequiredValue(image), time).Check();
            foreach (string problem in problems)
            {
                Out(parse).WriteLine(problem);
            }

            if (problems.Count == 0)
            {
                Out(parse).WriteLine("clean");
                return 0;
            }

            Err(parse).WriteLine(Invariant($"c5fs: {problems.Count} problem(s) found"));
            return Failure;
        }));

        return new RootCommand("Build and inspect C5FS floppy images for cp500-os")
        {
            format, info, ls, mkdir, put, get, rm, sys, check,
        };
    }

    private static Volume OpenImage(string path, TimeProvider time) => Volume.Open(File.ReadAllBytes(path), time);

    private static Volume Mutate(string path, TimeProvider time, Action<Volume> change)
    {
        Volume volume = OpenImage(path, time);
        change(volume);
        WriteAtomically(path, volume.ToImage());
        return volume;
    }

    /// <summary>Writes to a temporary file next to the target, then renames it over the target.</summary>
    private static void WriteAtomically(string path, byte[] content)
    {
        string full = Path.GetFullPath(path);
        string temp = Path.Combine(Path.GetDirectoryName(full)!, $".{Path.GetFileName(full)}.{Guid.NewGuid():N}.tmp");
        try
        {
            using (FileStream stream = new(temp, FileMode.CreateNew, FileAccess.Write))
            {
                stream.Write(content);
                stream.Flush(flushToDisk: true);
            }

            File.Move(temp, full, overwrite: true);
        }
        finally
        {
            File.Delete(temp);
        }
    }

    private static byte[]? ReadOptionalFile(string? path) => path is null ? null : File.ReadAllBytes(path);

    private static (string Path, byte[] Content)[] StagePuts(string[] specs)
    {
        var staged = new (string Path, byte[] Content)[specs.Length];
        for (int i = 0; i < specs.Length; i++)
        {
            string spec = specs[i];
            int split = spec.IndexOf('=');
            if (split <= 0 || split == spec.Length - 1)
            {
                throw new C5fsException(C5fsError.EINVAL, $"--put '{spec}' must be host=path");
            }

            staged[i] = (spec[(split + 1)..], File.ReadAllBytes(spec[..split]));
        }

        return staged;
    }

    private static void PutFile(Volume volume, string path, byte[] content)
    {
        VolumePath parsed = VolumePath.Parse(path);
        if (!parsed.Parent.IsRoot)
        {
            volume.CreateDirectory(parsed.Parent.ToString(), createParents: true);
        }

        volume.WriteFile(path, content);
    }

    private static void PrintInfo(TextWriter output, Volume volume)
    {
        Superblock superblock = volume.Superblock;
        VolumeGeometry geometry = volume.Geometry;
        string layout = geometry.Sides == 0
            ? "partition (no floppy geometry)"
            : $"{geometry.ImageSize / 1024} KiB floppy, {geometry.Sides} side(s), {geometry.Tracks} tracks, {geometry.SectorsPerTrack} sectors";
        (string Name, string Value)[] rows =
        [
            ("label", superblock.Label.Length == 0 ? "(none)" : superblock.Label),
            ("volume id", $"{superblock.VolumeId:X8}"),
            ("version", $"{Superblock.CurrentVersion}"),
            ("state", superblock.Clean ? "clean" : "dirty"),
            ("sequence", $"{superblock.Sequence} (copy {volume.ActiveCopy})"),
            ("generation", $"{superblock.Generation}"),
            ("geometry", layout),
            ("blocks", $"{geometry.BlockCount} total, {volume.FreeBlocks} free"),
            ("inodes", $"{geometry.InodeCount - 1} usable, {volume.FreeInodes} free"),
            ("bitmap", $"block {VolumeGeometry.BitmapStart}, {geometry.BitmapLength} block(s)"),
            ("inode table", $"blocks {geometry.InodeTableStart}-{geometry.FirstDataBlock - 1}"),
            ("first data", $"block {geometry.FirstDataBlock}"),
            ("kernel", superblock.Kernel is Extent run ? $"blocks {run} ({run.Length} blocks)" : "none"),
            ("boot sector", volume.ReadBootSector().AsSpan().ContainsAnyExcept((byte)0) ? "installed" : "empty"),
            ("created", superblock.Created.ToString()),
            ("last written", superblock.LastWritten.ToString()),
        ];
        foreach ((string name, string value) in rows)
        {
            output.WriteLine(Invariant($"{name,-13}{value}"));
        }
    }

    private static void PrintListing(TextWriter output, Volume volume, string path, bool longFormat)
    {
        FileStatus target = volume.Stat(path);
        IEnumerable<(string Name, FileStatus Status)> entries = target.Inode.IsDirectory
            ? volume.List(path).OrderBy(entry => entry.Name).Select(entry => (entry.Name.Value, entry.Status))
            : [(VolumePath.Parse(path).Name.Value, target)];
        foreach ((string name, FileStatus status) in entries)
        {
            output.WriteLine(longFormat ? LongLine(name, status) : name);
        }
    }

    private static string LongLine(string name, FileStatus status)
    {
        Inode inode = status.Inode;
        string mode = string.Concat(
            inode.IsDirectory ? "d" : "-",
            inode.Attributes.HasFlag(InodeAttributes.ReadOnly) ? "r" : "-",
            inode.Attributes.HasFlag(InodeAttributes.Hidden) ? "h" : "-");
        return Invariant($"{mode} {status.InodeNumber,4} {inode.Size,8} {inode.Modified.ToDateTime():yyyy-MM-dd HH:mm} {name}");
    }

    private static Func<ParseResult, int> Guarded(Action<ParseResult> action) =>
        parse => Guard(parse, () =>
        {
            action(parse);
            return 0;
        });

    private static int Guard(ParseResult parse, Func<int> action)
    {
        try
        {
            return action();
        }
        catch (C5fsException e)
        {
            Err(parse).WriteLine($"c5fs: {e.Error}: {e.Message}");
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Err(parse).WriteLine($"c5fs: {e.Message}");
        }

        return Failure;
    }

    private static TextWriter Out(ParseResult parse) => parse.InvocationConfiguration.Output;

    private static TextWriter Err(ParseResult parse) => parse.InvocationConfiguration.Error;

    private static string Invariant(FormattableString text) => text.ToString(CultureInfo.InvariantCulture);
}
