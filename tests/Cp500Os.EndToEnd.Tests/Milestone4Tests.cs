using System.Globalization;
using Cp500Os.C5fs;

namespace Cp500Os.EndToEnd.Tests;

public sealed class Milestone4Tests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("cp500-os-m4-").FullName;

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    [Fact]
    public async Task StubRomStillShowsThePrompt()
    {
        RunResult run = await Boot("sh>");
        Assert.Contains(Visible(run.Stdout), line => line == "sh>");
        Assert.Contains(Visible(run.Stdout), line => line == "cp500-os");
    }

    [Fact]
    public async Task ListingShowsAKnownName()
    {
        RunResult run = await Type("/bin/ls{ENTER}", "msg");
        Assert.Contains(Visible(run.Stdout), line => line == "msg");
        Assert.Contains(Visible(run.Stdout), line => line == "bin");
    }

    [Fact]
    public async Task CopyAndCatRoundTrip()
    {
        string image = CopyImage();
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image, "--write-back", "--timeout", "40s",
            "--until-screen", "sh>",
            "--type", "/bin/mkdir /work{ENTER}/bin/cp /home/note /work/n{ENTER}/bin/cat /work/n{ENTER}",
            "--until-screen", "hello",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Contains(Visible(run.Stdout), line => line == "hello");
        Assert.Equal(File.ReadAllBytes(Path.Combine(RepoPaths.Root, "programs", "hello.txt")), Volume.Open(File.ReadAllBytes(image)).ReadFile("/work/n"));
    }

    [Fact]
    public async Task MkdirRmAndMvChangeNames()
    {
        RunResult run = await Type(
            "/bin/mkdir /box{ENTER}/bin/cp /home/note /box/a{ENTER}/bin/mv /box/a /box/b{ENTER}/bin/cat /box/b{ENTER}/bin/rm /box/b{ENTER}/bin/rm /box{ENTER}/bin/ls /{ENTER}",
            "lib");
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line == "hello");
        Assert.Contains(lines, line => line == "lib");
        Assert.DoesNotContain(lines, line => line == "box");
    }

    [Fact]
    public async Task RemovingRootIsBusyAndAFullDirectoryIsNotEmpty()
    {
        RunResult busy = await Type("/bin/rm /{ENTER}", "EBUSY");
        Assert.Contains(Visible(busy.Stdout), line => line == "EBUSY");

        RunResult full = await Type("/bin/mkdir /full{ENTER}/bin/cp /home/note /full/a{ENTER}/bin/rm /full{ENTER}", "ENOTEMPTY");
        Assert.Contains(Visible(full.Stdout), line => line == "ENOTEMPTY");
    }

    [Fact]
    public async Task ReadOnlyFileRefusesACopy()
    {
        RunResult run = await Type("/bin/cp /home/note /msg{ENTER}", "EROFS");
        Assert.Contains(Visible(run.Stdout), line => line == "EROFS");
    }

    [Fact]
    public async Task DateSetsThePrintedTime()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(), "--timeout", "20s",
            "--until-screen", "sh>",
            "--type", "/bin/date 1980-01-01 00:00:00{ENTER}",
            "--run", "3s",
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Contains(Visible(run.Stdout), line => line == "1980-01-01 00:00:00");
    }

    [Fact]
    public async Task DateWithoutArgumentsFollowsTheVolumeClock()
    {
        string image = CopyImage();
        uint lastWritten = Volume.Open(File.ReadAllBytes(image)).Superblock.LastWritten.Seconds;
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image, "--timeout", "40s",
            "--until-screen", "sh>",
            "--type", "/bin/date{ENTER}",
            "--run", "3s",
            "--dump-memory", "F7F0:8",
            "--dump-memory", $"{ClockBase():X4}:8",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        byte[] memory = run.DumpedMemory();
        uint tick = BitConverter.ToUInt32(memory, 0);
        uint seconds = BitConverter.ToUInt32(memory, 4);
        uint origin = BitConverter.ToUInt32(memory, 8);
        uint originTick = BitConverter.ToUInt32(memory, 12);
        Assert.Equal(lastWritten, origin);
        Assert.Equal(origin + (tick - originTick) / 30, seconds);
        Assert.Contains(Visible(run.Stdout), line => line == new C5Time(seconds).ToString());
    }

    [Fact]
    public async Task MoreAdvancesOnSpace()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(), "--timeout", "40s",
            "--until-screen", "sh>",
            "--type", "/bin/more /home/lines{ENTER}",
            "--until-screen", "row-01",
            "--type", " ",
            "--until-screen", "row-17",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Contains(Visible(run.Stdout), line => line == "row-17");
    }

    [Fact]
    public async Task EditorWritesTheChangedByte()
    {
        string image = CopyImage();
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image, "--write-back", "--timeout", "40s",
            "--until-screen", "sh>",
            "--type", "/bin/ed /home/note{ENTER}H:w{ENTER}/bin/cat /home/note{ENTER}",
            "--until-screen", "Hello",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Contains(Visible(run.Stdout), line => line == "Hello");
        byte[] note = File.ReadAllBytes(Path.Combine(RepoPaths.Root, "programs", "hello.txt"));
        note[0] = (byte)'H';
        Assert.Equal(note, Volume.Open(File.ReadAllBytes(image)).ReadFile("/home/note"));
    }

    private string CopyImage()
    {
        string path = Path.Combine(_directory, "disk.dsk");
        File.Copy(Product(), path);
        return path;
    }

    private static async Task<RunResult> Boot(string until)
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", until, "--timeout", "20s",
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        return run;
    }

    private static async Task<RunResult> Type(string typed, string until)
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "40s",
            "--type", typed, "--until-screen", until,
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        return run;
    }

    private static ushort ClockBase()
    {
        string sym = File.ReadAllText(Path.Combine(RepoPaths.Root, "build", "z80", "kernel.sym"));
        int mark = sym.IndexOf("clk_base: EQU 0x", StringComparison.Ordinal);
        Assert.True(mark >= 0);
        return ushort.Parse(sym.AsSpan(mark + "clk_base: EQU 0x".Length, 8), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }

    private static string Product() => Path.Combine(RepoPaths.Root, "build", "cp500-os.dsk");

    private static string[] Visible(string stdout) =>
    [
        .. stdout.Split('\n')
            .Select(line => line.Replace("\U0001FB2D", "").TrimEnd(' ', '\r'))
            .Where(line => line.Length > 0 && !(line.Length > 5 && line[4] == ':' &&
                int.TryParse(line.AsSpan(0, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out _))),
    ];
}
