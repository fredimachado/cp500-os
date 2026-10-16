using Cp500Os.C5fs.Cli;
using static Cp500Os.C5fs.Tests.TestSupport;

namespace Cp500Os.C5fs.Tests;

public sealed class CliTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("c5fs-cli-").FullName;

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    [Fact]
    public void FormatAndInfoShowTheSuperblock()
    {
        string image = PathOf("disk.img");

        (int exit, string output, string error) = Run("format", image, "--size", "180", "--label", "CP500");

        Assert.Equal((0, ""), (exit, error));
        Assert.Equal(184_320, new FileInfo(image).Length);
        uint id = Volume.Open(File.ReadAllBytes(image)).Superblock.VolumeId;
        Assert.Equal($"{image}: 180 KiB, 720 blocks, 64 inodes, volume id {id:X8}{Environment.NewLine}", output);
        Assert.Equal(
            Lines(
                "label        CP500",
                $"volume id    {id:X8}",
                "version      1",
                "state        clean",
                "sequence     2 (copy B)",
                "generation   1",
                "geometry     180 KiB floppy, 1 side(s), 40 tracks, 18 sectors",
                "blocks       720 total, 707 free",
                "inodes       63 usable, 62 free",
                "bitmap       block 3, 1 block(s)",
                "inode table  blocks 4-11",
                "first data   block 12",
                "kernel       none",
                "boot sector  empty",
                "created      2026-10-16 10:00:00",
                "last written 2026-10-16 10:00:00"),
            Run("info", image).Output);
    }

    [Fact]
    public void EndToEndSessionBuildsAConsistentImage()
    {
        string image = PathOf("disk.img");
        byte[] notes = Pattern(1000, 3);
        byte[] kernel = Pattern(1000, 9);
        File.WriteAllBytes(PathOf("notes.txt"), notes);
        File.WriteAllBytes(PathOf("kernel.bin"), kernel);

        Assert.Equal(0, Run("format", image).Exit);
        Assert.Equal((0, "", ""), Run("mkdir", image, "/home/fredi", "-p"));
        Assert.Equal((0, "", ""), Run("put", image, PathOf("notes.txt"), "/home/fredi/notes.txt"));
        Assert.Equal((0, "", ""), Run("put", image, PathOf("notes.txt"), "/README"));
        Assert.Equal(
            (0, Lines("d--    2       64 2026-10-16 10:00 home", "---    5     1000 2026-10-16 10:00 README"), ""),
            Run("ls", image, "/", "-l"));
        Assert.Equal((0, Lines("notes.txt"), ""), Run("ls", image, "/home/fredi"));
        Assert.Equal((0, Lines("notes.txt"), ""), Run("ls", image, "/home/fredi/notes.txt"));
        Assert.Equal((0, "", ""), Run("get", image, "/HOME/fredi/NOTES.TXT", PathOf("copy.txt")));
        Assert.Equal(notes, File.ReadAllBytes(PathOf("copy.txt")));
        Assert.Equal((0, Lines("kernel: blocks 32-35 (4 blocks, 1000 bytes)"), ""), Run("sys", image, "--kernel", PathOf("kernel.bin")));
        Assert.Contains($"kernel       blocks 32-35 (4 blocks){Environment.NewLine}", Run("info", image).Output, StringComparison.Ordinal);
        Assert.Equal((0, "", ""), Run("rm", image, "/README"));
        Assert.Equal((0, Lines("clean"), ""), Run("check", image));

        Volume volume = Volume.Open(File.ReadAllBytes(image));
        Assert.Equal(kernel, volume.ReadFile("/sys/kernel"));
        Assert.Equal(new Extent(32, 4), volume.Superblock.Kernel);
        Assert.Equal(6, volume.Superblock.Generation);
        Assert.Empty(volume.Check());
    }

    [Fact]
    public void AFailingPutLeavesTheImageByteIdentical()
    {
        string image = PathOf("disk.img");
        Run("format", image, "--size", "180");
        File.WriteAllBytes(PathOf("big.bin"), Pattern(708 * 256));
        File.WriteAllBytes(PathOf("small.bin"), Pattern(10));
        byte[] before = File.ReadAllBytes(image);

        Assert.Equal((1, "", Lines("c5fs: ENOSPC: no space: 708 blocks needed, 707 free")), Run("put", image, PathOf("big.bin"), "/big"));
        Assert.Equal((1, "", Lines("c5fs: ENOENT: '/missing' does not exist")), Run("put", image, PathOf("small.bin"), "/missing/f"));
        (int exit, _, string error) = Run("put", image, PathOf("absent.bin"), "/f");
        Assert.Equal(1, exit);
        Assert.Contains("absent.bin", error, StringComparison.Ordinal);

        Assert.Equal(before, File.ReadAllBytes(image));
        Assert.Equal(["big.bin", "disk.img", "small.bin"], Directory.GetFiles(_directory).Select(Path.GetFileName).Order());
    }

    [Fact]
    public void ErrorsGoToStandardErrorWithTheKernelErrorName()
    {
        string image = PathOf("disk.img");
        Run("format", image);
        Run("mkdir", image, "/d");

        Assert.Equal((1, "", Lines("c5fs: EISDIR: '/d' is a directory")), Run("get", image, "/d", PathOf("out")));
        Assert.False(File.Exists(PathOf("out")));
        Assert.Equal((1, "", Lines("c5fs: EEXIST: '/d' already exists")), Run("mkdir", image, "/d"));
        Assert.Equal((1, "", Lines("c5fs: EINVAL: sys needs --boot, --kernel or both")), Run("sys", image));
        Assert.Equal(1, Run("info", PathOf("missing.img")).Exit);
        Assert.Equal((0, Lines("clean"), ""), Run("check", image));
    }

    [Fact]
    public void ParseErrorsFailWithoutCreatingTheImage()
    {
        (int exit, _, string error) = Run("format", PathOf("disk.img"), "--size", "720");

        Assert.NotEqual(0, exit);
        Assert.Contains("720", error, StringComparison.Ordinal);
        Assert.False(File.Exists(PathOf("disk.img")));
    }

    [Fact]
    public void CheckListsProblemsAndExitsWithOne()
    {
        string image = PathOf("disk.img");
        Run("format", image);
        byte[] bytes = File.ReadAllBytes(image);
        bytes[(3 * 256) + 100] |= 0x01;
        File.WriteAllBytes(image, bytes);

        Assert.Equal(
            (1, Lines("block 800 is marked used but nothing owns it"), Lines("c5fs: 1 problem(s) found")),
            Run("check", image));
    }

    [Fact]
    public void BootSectorsInstallAtFormatAndThroughSys()
    {
        string image = PathOf("disk.img");
        File.WriteAllBytes(PathOf("boot.bin"), Pattern(10, 4));
        File.WriteAllBytes(PathOf("boot2.bin"), Pattern(256, 5));

        Run("format", image, "--boot", PathOf("boot.bin"));
        byte[] formatted = File.ReadAllBytes(image);
        Assert.Equal(Pattern(10, 4), formatted[..10]);
        Assert.Equal(1, Volume.Open(formatted).Superblock.Generation);

        Assert.Equal((0, "", ""), Run("sys", image, "--boot", PathOf("boot2.bin")));
        byte[] updated = File.ReadAllBytes(image);
        Assert.Equal(Pattern(256, 5), updated[..256]);
        Assert.Equal(2, Volume.Open(updated).Superblock.Generation);
        Assert.Contains("boot sector  installed", Run("info", image).Output, StringComparison.Ordinal);
    }

    [Fact]
    public void ListingIsSortedCaseInsensitively()
    {
        string image = PathOf("disk.img");
        Run("format", image);
        foreach (string name in new[] { "zeta", "Beta", "alpha", "Ação", "Acao" })
        {
            Run("mkdir", image, "/" + name);
        }

        Assert.Equal((0, Lines("Acao", "alpha", "Ação", "Beta", "zeta"), ""), Run("ls", image));
    }

    private string PathOf(string name) => Path.Combine(_directory, name);

    private static string Lines(params string[] lines) => string.Concat(lines.Select(line => line + Environment.NewLine));

    private static (int Exit, string Output, string Error) Run(params string[] args)
    {
        using StringWriter output = new();
        using StringWriter error = new();
        int exit = C5fsCli.Run(args, output, error, Clock());
        return (exit, output.ToString(), error.ToString());
    }
}
