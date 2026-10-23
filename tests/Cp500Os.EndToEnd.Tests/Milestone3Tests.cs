using System.Globalization;
using Cp500Os.C5fs;
using Cp500Os.C5x;

namespace Cp500Os.EndToEnd.Tests;

public sealed class Milestone3Tests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("cp500-os-m3-").FullName;

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    [Fact]
    public void KernelImageIs8KiBAndTheSectorBufferIsEmpty()
    {
        byte[] kernel = RepoPaths.ReadZ80Output("kernel.bin");
        Assert.Equal(8192, kernel.Length);
        Assert.Contains(
            "BLK_BUF: EQU 0x00006100",
            File.ReadAllText(RepoPaths.Z80Output("kernel.sym")),
            StringComparison.Ordinal);
        Assert.All(kernel.Skip(0x6100 - 0x4200), b => Assert.Equal(0, b));
    }

    [Fact]
    public async Task StubRomShowsThePromptAndTheShellImage()
    {
        C5xProgram shell = Load("sh.c5x");
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--dump-screen",
            "--dump-memory", $"6200:{shell.Header.ImageSize}");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line == "CP-500 OS v1.1");
        Assert.Contains(lines, line => line == "sh>");
        Assert.Equal(shell.RelocateTo(0x62), run.DumpedMemory());
    }

    [Fact]
    public async Task SampleProgramPrintsItsLinesAndExitsWith3()
    {
        RunResult run = await TypeAsync("/bin/hi{ENTER}", "exit 3");
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line == "sh>");
        Assert.Contains(lines, line => line == "hello");
        Assert.Contains(lines, line => line == "c5fs-ok");
        Assert.Contains(lines, line => line == "bin");
        Assert.Contains(lines, line => line == "EROFS");
        Assert.Contains(lines, line => line == "/");
        Assert.Contains(lines, line => line == "/bin");
        Assert.Contains(lines, line => line == "ENOTDIR");
        Assert.Contains(lines, line => line == "ok");
        Assert.Contains(lines, line => line == "exit 3");
    }

    [Fact]
    public async Task WriteOpenOfAFileIsReadOnly()
    {
        RunResult run = await TypeAsync("> /bin/hi{ENTER}", "EROFS");
        Assert.Contains(Visible(run.Stdout), line => line == "EROFS");
    }

    [Fact]
    public async Task MissingParentIsNotFound()
    {
        RunResult run = await TypeAsync("> /no/such{ENTER}", "ENOENT");
        Assert.Contains(Visible(run.Stdout), line => line == "ENOENT");
    }

    [Fact]
    public async Task KernelFileIsNotExecutable()
    {
        RunResult run = await TypeAsync("/sys/kernel{ENTER}", "ENOEXEC");
        Assert.Contains(Visible(run.Stdout), line => line == "ENOEXEC");
    }

    [Fact]
    public async Task MissingProgramIsNotFound()
    {
        RunResult run = await TypeAsync("/bin/missing{ENTER}", "ENOENT");
        Assert.Contains(Visible(run.Stdout), line => line == "ENOENT");
    }

    [Fact]
    public async Task BareNameRunsFromBin()
    {
        RunResult run = await TypeAsync("hi{ENTER}", "exit 3");
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line == "hello");
        Assert.Contains(lines, line => line == "c5fs-ok");
        Assert.Contains(lines, line => line == "exit 3");
    }

    [Fact]
    public async Task BareLsListsHomeLikeAbsolutePath()
    {
        RunResult run = await TypeAsync("ls /home{ENTER}", "lines");
        Assert.Contains(Visible(run.Stdout), line => line == "lines");
    }

    [Fact]
    public async Task BareMissingProgramIsNotFound()
    {
        RunResult run = await TypeAsync("nosuch{ENTER}", "ENOENT");
        Assert.Contains(Visible(run.Stdout), line => line == "ENOENT");
    }

    [Fact]
    public async Task SpawnWithoutWaitRunsTheRelocatedSample()
    {
        C5xProgram shell = Load("sh.c5x");
        C5xProgram sample = Load("reloc.c5x");
        int childPage = 0x62 + shell.Header.MemoryPages;
        int counter = SampleSymbol("counter");
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "? /lib/reloc.c5x{ENTER}", "--until-screen", "ok 2",
            "--dump-screen",
            "--dump-memory", $"{childPage * 256:X4}:{counter}");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Contains(Visible(run.Stdout), line => line == "ok 2");
        Assert.Equal(sample.RelocateTo((byte)childPage)[..counter], run.DumpedMemory());
    }

    [Fact]
    public async Task KernelOnlyDiskHaltsOnTheBanner()
    {
        string image = Path.Combine(_directory, "kernel-only.dsk");
        Volume volume = Volume.Format(new FormatOptions { Geometry = VolumeGeometry.Floppy180, Label = "CP500" });
        volume.InstallBootSector(RepoPaths.ReadZ80Output("boot.bin"));
        volume.InstallKernel(RepoPaths.ReadZ80Output("kernel.bin"));
        File.WriteAllBytes(image, volume.ToImage());

        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image,
            "--until-screen", "CP-500 OS v1.1", "--timeout", "15s",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line == "CP-500 OS v1.1");
        Assert.DoesNotContain(lines, line => line == "sh>");
        Assert.DoesNotContain(lines, line => line == "M");
    }

    [Fact]
    public async Task RealRomRunsTheSample()
    {
        string rom = Roms.RequireReal();
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", rom, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "30s",
            "--type", "/bin/hi{ENTER}", "--until-screen", "exit 3",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line == "hello");
        Assert.Contains(lines, line => line == "c5fs-ok");
        Assert.Contains(lines, line => line == "exit 3");
    }

    private static async Task<RunResult> TypeAsync(string typed, string until)
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", typed, "--until-screen", until,
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        return run;
    }

    private static C5xProgram Load(string name) => C5xFile.Parse(RepoPaths.ReadZ80Output(name));

    private static int SampleSymbol(string name)
    {
        string prefix = name + ": EQU 0x";
        string line = File.ReadLines(RepoPaths.Z80Output("reloc-sample-0000.sym")).Single(l => l.StartsWith(prefix, StringComparison.Ordinal));
        return int.Parse(line.AsSpan(prefix.Length), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }

    private static string Product() => Path.Combine(RepoPaths.Root, "build", "cp500-os.dsk");

    private static string[] Visible(string stdout) =>
    [
        .. stdout.Split('\n')
            .Select(line => line.Replace("\U0001FB2D", "").TrimEnd(' ', '\r'))
            .Where(line => line.Length > 0 && !IsDump(line)),
    ];

    private static bool IsDump(string line) =>
        line.Length > 5 && line[4] == ':' &&
        int.TryParse(line.AsSpan(0, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out _);
}
