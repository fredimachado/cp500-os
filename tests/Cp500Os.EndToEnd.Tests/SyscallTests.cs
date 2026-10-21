using System.Globalization;
using Cp500Os.C5x;

namespace Cp500Os.EndToEnd.Tests;

public sealed class SyscallTests
{
    [Fact]
    public async Task SleepZeroExitsZero()
    {
        RunResult run = await RunFixtureAsync("/lib/syscalltest.c5x z", "ok");
        AssertOk(run);
    }

    [Fact]
    public async Task SleepFourExitsZero()
    {
        RunResult run = await RunFixtureAsync("/lib/syscalltest.c5x s", "ok");
        AssertOk(run);
    }

    [Fact]
    public async Task UptimeExitsZero()
    {
        RunResult run = await RunFixtureAsync("/lib/syscalltest.c5x u", "ok");
        AssertOk(run);
    }

    [Fact]
    public async Task MeminfoExitsZero()
    {
        RunResult run = await RunFixtureAsync("/lib/syscalltest.c5x m", "ok");
        AssertOk(run);
    }

    [Fact]
    public async Task AllocFreeExitsZero()
    {
        RunResult run = await RunFixtureAsync("/lib/syscalltest.c5x a", "ok");
        AssertOk(run);
    }

    [Fact]
    public async Task UnalignedFreeExitsEinval()
    {
        RunResult run = await RunFixtureAsync("/lib/syscalltest.c5x f", "exit 5");
        AssertExit(run, 5);
    }

    [Fact]
    public async Task BadDup2ExitsEbadf()
    {
        RunResult run = await RunFixtureAsync("/lib/syscalltest.c5x b", "exit 4");
        AssertExit(run, 4);
    }

    [Fact]
    public async Task Dup2WriteShowsQ()
    {
        RunResult run = await RunFixtureAsync("/lib/syscalltest.c5x d", "ok");
        AssertOk(run);
        Assert.Contains(Visible(run.Stdout), line => line.Contains('Q'));
    }

    [Fact]
    public async Task Dup2SharesSer0()
    {
        SerialBoard.Require();
        RunResult run = await RunFixtureAsync("/lib/syscalltest.c5x r", "ok");
        AssertOk(run);
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

    private static void AssertOk(RunResult run)
    {
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line == "ok");
        Assert.DoesNotContain(lines, line => line.StartsWith("exit ", StringComparison.Ordinal));
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
