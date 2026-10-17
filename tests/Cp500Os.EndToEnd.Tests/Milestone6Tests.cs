using System.Globalization;
using Cp500Os.C5x;

namespace Cp500Os.EndToEnd.Tests;

public sealed class Milestone6Tests
{
    private const byte TsBlocked = 2;
    private const byte ChTick = 2;

    [Fact]
    public async Task OpeningSer0WithoutABoardIsEnodev()
    {
        RunResult run = await RunFixtureAsync("/lib/sertest.c5x", "exit 18");
        AssertExit(run, 18);
    }

    [Theory]
    [InlineData("c")]
    [InlineData("t")]
    [InlineData("a")]
    [InlineData("x")]
    public async Task DeviceOpenRejectsFileFlags(string flag)
    {
        RunResult run = await RunFixtureAsync($"/lib/sertest.c5x {flag}", "exit 5");
        AssertExit(run, 5);
    }

    [Fact]
    public async Task TermWithoutABoardReportsEnodev()
    {
        RunResult run = await RunFixtureAsync("/bin/term", "exit 18");
        AssertExit(run, 18);
    }

    [Fact]
    public async Task PollTimeoutZeroChecksOnce()
    {
        RunResult run = await RunFixtureAsync("/lib/polltest.c5x 0", "exit 128");
        AssertExit(run, 128);
    }

    [Fact]
    public async Task PollTimeoutWaitsItsTicks()
    {
        RunResult run = await RunFixtureAsync("/lib/polltest.c5x t", "exit 128");
        AssertExit(run, 128);
        Assert.DoesNotContain(Visible(run.Stdout), line => line == "exit 9");
    }

    [Fact]
    public async Task PollForeverReturnsOnAKey()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "/lib/polltest.c5x k{ENTER}",
            "--type", "x",
            "--until-screen", "exit 129",
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        AssertExit(run, 129);
    }

    [Fact]
    public async Task PollWaitBlocksTheTask()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "/lib/polltest.c5x k{ENTER}",
            "--run", "1s",
            "--dump-memory", "40A8:16");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        byte[] mem = run.DumpedMemory();
        bool blocked = false;
        for (int slot = 0; slot < 8; slot++)
        {
            if (mem[slot] == TsBlocked && mem[8 + slot] == ChTick)
                blocked = true;
        }
        Assert.True(blocked, "Expected a task blocked on CH_TICK");
    }

    [Fact]
    public async Task PollSeesPipeHangup()
    {
        RunResult run = await RunFixtureAsync("/lib/polltest.c5x p", "exit 133");
        AssertExit(run, 133);
    }

    [Fact]
    public async Task PollMarksABadFd()
    {
        RunResult run = await RunFixtureAsync("/lib/polltest.c5x n", "exit 144");
        AssertExit(run, 144);
    }

    [Fact]
    public async Task PollConsoleOutputIsWritable()
    {
        RunResult run = await RunFixtureAsync("/lib/polltest.c5x w", "exit 130");
        AssertExit(run, 130);
    }

    [Fact]
    public async Task PollFileIsReadyBothWays()
    {
        RunResult run = await RunFixtureAsync("/lib/polltest.c5x f", "exit 131");
        AssertExit(run, 131);
    }

    [Fact]
    public async Task PollCountOutOfRangeIsEinval()
    {
        RunResult run = await RunFixtureAsync("/lib/polltest.c5x b", "exit 5");
        AssertExit(run, 5);
    }

    [Fact]
    public async Task SerialIoctlOnAConsoleIsEinval()
    {
        RunResult run = await RunFixtureAsync("/lib/sertest.c5x i", "exit 5");
        AssertExit(run, 5);
    }

    [Fact]
    public async Task SerialBoardOpensAndSharesAcrossSpawn()
    {
        SerialBoard.Require();
        RunResult run = await RunFixtureAsync("/lib/serboard.c5x", "exit 100");
        AssertExit(run, 100);
    }

    [Fact]
    public async Task TermDialsAnsweringModem()
    {
        SerialBoard.Require();
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "30s",
            "--type", "/bin/term{ENTER}",
            "--run", "5s",
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line.StartsWith("CONNECT", StringComparison.Ordinal) || line.Contains("CONNECT"));
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

internal static class SerialBoard
{
    public static void Require()
    {
        RunResult probe = HeadlessRunner.RunAsync(
            "--rom", Roms.Stub,
            "--disk0", Path.Combine(RepoPaths.Root, "build", "cp500-os.dsk"),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "/lib/sertest.c5x{ENTER}",
            "--until-screen", "exit",
            "--dump-screen").GetAwaiter().GetResult();
        string[] lines = probe.Stdout.Split('\n')
            .Select(line => line.Replace("\u2588", "").TrimEnd(' ', '\r'))
            .Where(line => line.StartsWith("exit ", StringComparison.Ordinal))
            .ToArray();
        if (lines.Any(line => line == "exit 18"))
            Assert.Skip("pinned heh8080 has no UART; dial path not run");
    }
}
