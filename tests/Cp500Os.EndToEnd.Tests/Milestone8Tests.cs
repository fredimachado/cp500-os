using Cp500Os.Tests;

namespace Cp500Os.EndToEnd.Tests;

public sealed class Milestone8Tests
{
    [Fact]
    public async Task SocketWithoutABoardIsEnodev()
    {
        RunResult run = await RunFixtureAsync("/lib/nettest.c5x", "exit 18");
        AssertExit(run, 18);
    }

    [Fact]
    public async Task BadSocketTypeIsEinval()
    {
        RunResult run = await RunFixtureAsync("/lib/nettest.c5x t", "exit 5");
        AssertExit(run, 5);
    }

    [Fact]
    public async Task ReservedSocketCallIsEinval()
    {
        RunResult run = await RunFixtureAsync("/lib/nettest.c5x b", "exit 5");
        AssertExit(run, 5);
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
        int.TryParse(line.AsSpan(0, 4), System.Globalization.NumberStyles.HexNumber, null, out _);
}

internal static class W5100Board
{
    private static bool? _accepted;

    public static void Require()
    {
        if (_accepted ??= Probe())
            return;

        Assert.Skip("pinned heh8080 has no W5100; network path was not run");
    }

    private static bool Probe()
    {
        string exe = Path.Combine(AppContext.BaseDirectory, OperatingSystem.IsWindows() ? "heh8080-cp500.exe" : "heh8080-cp500");
        var startInfo = new System.Diagnostics.ProcessStartInfo(exe)
        {
            RedirectStandardOutput = true,
            UseShellExecute = false,
            ArgumentList = { "--help" },
        };
        using var process = System.Diagnostics.Process.Start(startInfo) ?? throw new InvalidOperationException("Could not start runner.");
        string text = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        return text.Contains("--w5100", StringComparison.Ordinal);
    }
}
