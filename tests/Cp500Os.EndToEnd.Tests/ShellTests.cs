namespace Cp500Os.EndToEnd.Tests;

public sealed class ShellTests
{
    [Fact]
    public async Task BackspaceEditsLine()
    {
        RunResult run = await TypeAsync("ab{BS}c{ENTER}? /lib/syscalltest.c5x z{ENTER}", "ok");
        AssertOk(run);
    }

    [Fact]
    public async Task HistoryRecallsPriorLine()
    {
        RunResult run = await TypeAsync("histline{ENTER}{UP}{ENTER}? /lib/syscalltest.c5x z{ENTER}", "ok");
        AssertOk(run);
    }

    [Fact]
    public async Task TabListsTwoBinMatches()
    {
        RunResult run = await TypeAsync("c{TAB}", "cat");
        string[] lines = Visible(run.Stdout);
        Assert.Contains("cat", lines);
        Assert.Contains("cp", lines);
        Assert.Contains("sh>c", lines);
    }

    [Fact]
    public async Task RedirectWritesFile()
    {
        RunResult run = await TypeAsync("? /lib/syscalltest.c5x z > /tmp/out{ENTER}/bin/cat /tmp/out{ENTER}", "ok");
        AssertOk(run);
    }

    [Fact]
    public async Task DuplicateHistoryEntryIsNotStored()
    {
        RunResult run = await TypeAsync(
            "dup{ENTER}dup{ENTER}{UP}{ENTER}? /lib/syscalltest.c5x z{ENTER}",
            "ok");
        AssertOk(run);
    }

    private static async Task<RunResult> TypeAsync(string typed, string until)
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", typed,
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
