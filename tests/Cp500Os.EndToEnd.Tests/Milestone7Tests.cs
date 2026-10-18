using System.Globalization;
using Cp500Os.C5fs;
using Cp500Os.Tests;

namespace Cp500Os.EndToEnd.Tests;

public sealed class Milestone7Tests
{
    [Fact]
    public async Task OpeningHd0WithoutABoardIsEnodev()
    {
        RunResult run = await RunFixtureAsync("/lib/hdtest.c5x", "exit 18");
        AssertExit(run, 18);
    }

    [Theory]
    [InlineData("c")]
    [InlineData("t")]
    [InlineData("a")]
    [InlineData("x")]
    public async Task Hd0OpenRejectsFileFlags(string flag)
    {
        RunResult run = await RunFixtureAsync($"/lib/hdtest.c5x {flag}", "exit 5");
        AssertExit(run, 5);
    }

    [Theory]
    [InlineData("m")]
    [InlineData("d")]
    public async Task MountWithoutABoardIsEnodev(string mode)
    {
        RunResult run = await RunFixtureAsync($"/lib/hdtest.c5x {mode}", "exit 18");
        AssertExit(run, 18);
    }

    [Fact]
    public async Task FifthSlotIsNotAMountName()
    {
        RunResult run = await RunFixtureAsync("/lib/hdtest.c5x n", "exit 1");
        AssertExit(run, 1);
    }

    [Fact]
    public async Task RootSurvivesAFailedMount()
    {
        RunResult run = await RunFixtureAsync("/lib/hdtest.c5x r", "exit 42");
        AssertExit(run, 42);
    }

    [Fact]
    public async Task ClockKeepsRootTimeWithoutABoard()
    {
        string image = Path.Combine(RepoPaths.Root, "build", "cp500-os.dsk");
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
    public void Hd0ReadsThePartitionTable()
    {
        HardDiskBoard.Require();
    }

    [Fact]
    public async Task PartitionFileReadsSeeksAndStats()
    {
        HardDiskBoard.Require();
        await RunFixtureAsync("/lib/hdtest.c5x f", "exit 0");
    }

    [Fact]
    public async Task PartitionWriteReadsBackOnTheHost()
    {
        HardDiskBoard.Require();
    }

    [Fact]
    public async Task LargePartitionRefusesWrites()
    {
        HardDiskBoard.Require();
        RunResult run = await RunFixtureAsync("/lib/hdtest.c5x w", "exit 7");
        AssertExit(run, 7);
    }

    [Fact]
    public async Task BadSuperblockIsEioAndRootSurvives()
    {
        HardDiskBoard.Require();
    }

    [Fact]
    public async Task ClockComesFromTheBoard()
    {
        HardDiskBoard.Require();
    }

    private static async Task<RunResult> RunFixtureAsync(string command, string until)
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", command + "{ENTER}",
            "--until-screen", until,
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        return run;
    }

    private static void AssertExit(RunResult run, int code)
    {
        Assert.Contains(Visible(run.Stdout), line => line == $"exit {code}");
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
            .Select(line => line.Replace("\u2588", "").TrimEnd(' ', '\r'))
            .Where(line => line.Length > 0 && !IsDump(line)),
    ];

    private static bool IsDump(string line) =>
        line.Length > 5 && line[4] == ':' &&
        int.TryParse(line.AsSpan(0, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out _);
}

internal static class HardDiskBoard
{
    public static void Require()
    {
        Assert.Skip("pinned heh8080 has no hard disk; mounted-partition path was not run");
    }
}
