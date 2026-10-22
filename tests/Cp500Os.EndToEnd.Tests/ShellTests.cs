namespace Cp500Os.EndToEnd.Tests;

public sealed class ShellTests
{
    [Fact]
    public async Task BackspaceEditsLine()
    {
        RunResult run = await TypeAsync("ab{BS}c{ENTER}/lib/syscalltest.c5x z{ENTER}", "ok");
        AssertOk(run);
    }

    [Fact]
    public async Task LeftArrowErasesLikeBackspace()
    {
        RunResult run = await TypeAsync("lss{LEFT}{ENTER}", "bin");
        Assert.Contains("sh>ls", Visible(run.Stdout));
    }

    [Fact]
    public async Task ErasedCharactersLeaveTheScreen()
    {
        RunResult run = await TypeAsync("abcd{LEFT}{LEFT}", "sh>ab");
        Assert.Equal("sh>ab", Visible(run.Stdout)[^1]);
    }

    [Fact]
    public async Task HistoryRecallsPriorLine()
    {
        RunResult run = await TypeAsync("histline{ENTER}{UP}{ENTER}/lib/syscalltest.c5x z{ENTER}", "ok");
        AssertOk(run);
        Assert.Equal(2, Visible(run.Stdout).Count(line => line == "sh>histline"));
    }

    [Fact]
    public async Task DownPastNewestClearsLine()
    {
        RunResult run = await TypeAsync("one{ENTER}two{ENTER}{UP}{UP}{DOWN}{DOWN}x", "sh>x");
        Assert.Contains("sh>x", Visible(run.Stdout));
    }

    [Fact]
    public async Task FifthLineKeepsHistoryOffTheScreen()
    {
        RunResult run = await TypeAsync("aa{ENTER}bb{ENTER}cc{ENTER}dd{ENTER}ee{ENTER}{UP}", "sh>ee");
        string[] lines = Visible(run.Stdout);
        Assert.DoesNotContain(lines, line => line.StartsWith(' '));
        Assert.Equal("sh>ee", lines[^1]);
    }

    [Fact]
    public async Task ErrorLeavesCursorOnPromptRow()
    {
        RunResult run = await TypeAsync("nosuch{ENTER}", "ENOENT");
        string[] rows = [.. run.Stdout.Split('\n').Select(line => line.TrimEnd(' ', '\r')).Where(line => line.Length > 0)];
        Assert.Equal("sh>", rows[^1].Replace("\U0001FB2D", ""));
    }

    [Fact]
    public async Task NoCaretWhileTheShellLoads()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "CP-500 OS v1.0", "--timeout", "10s",
            "--run", "600ms",
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.DoesNotContain("sh>", run.Stdout);
        Assert.DoesNotContain("\U0001FB2D", run.Stdout);
    }

    [Fact]
    public async Task CaretIsTheCp500BarAfterThePrompt()
    {
        // B0h, on from the 7th tick after sh> to the 14th.
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--run", "300ms",
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Contains(run.Stdout.Split('\n'), line => line.TrimEnd(' ', '\r') == "sh>\U0001FB2D");
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
    public async Task TabCompletesTheOneBinMatch()
    {
        RunResult run = await TypeAsync("ca{TAB} /home/note{ENTER}", "hello");
        Assert.Contains("sh>cat /home/note", Visible(run.Stdout));
    }

    [Fact]
    public async Task TabCompletesAnAbsolutePath()
    {
        RunResult run = await TypeAsync("cat /home/n{TAB}{ENTER}", "hello");
        Assert.Contains("sh>cat /home/note", Visible(run.Stdout));
    }

    [Fact]
    public async Task TabAddsSlashAfterADirectory()
    {
        RunResult run = await TypeAsync("ls /h{TAB}{ENTER}", "irc-demo");
        Assert.Contains("sh>ls /home/", Visible(run.Stdout));
    }

    [Fact]
    public async Task RedirectsDoNotLeakDescriptors()
    {
        string nine = string.Concat(Enumerable.Repeat("ls /tmp > /tmp/o{ENTER}", 9));
        RunResult run = await TypeAsync(nine + "/bin/cat /home/note{ENTER}", "hello");
        Assert.DoesNotContain("EMFILE", Visible(run.Stdout));
    }

    [Fact]
    public async Task CopiedMultiBlockProgramRuns()
    {
        // Do not until-screen on ":" - the banner URL already contains "https:".
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "/bin/cp /bin/date /tmp/d{ENTER}/tmp/d{ENTER}",
            "--run", "10s",
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line.Length == 19 && line[4] == '-' && line[13] == ':');
        Assert.DoesNotContain(lines, line => line.StartsWith("exit ", StringComparison.Ordinal));
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
            "first{ENTER}dup{ENTER}dup{ENTER}{UP}{UP}{ENTER}/lib/syscalltest.c5x z{ENTER}",
            "ok");
        AssertOk(run);
        Assert.Equal(2, Visible(run.Stdout).Count(line => line == "sh>first"));
    }

    [Fact]
    public async Task UpPastOldestKeepsLine()
    {
        RunResult run = await TypeAsync("only{ENTER}{UP}{UP}{UP}", "sh>only");
        Assert.Equal("sh>only", Visible(run.Stdout)[^1]);
    }

    [Fact]
    public void ShellStaysInThirteenArenaPages()
    {
        // Every child loads above the shell; one more page leaves irc too little room.
        var shell = Cp500Os.C5x.C5xFile.Parse(RepoPaths.ReadZ80Output("sh.c5x"));
        Assert.True(shell.Header.MemoryPages <= 13, $"/bin/sh needs {shell.Header.MemoryPages} pages");
    }

    private static async Task<RunResult> TypeAsync(string typed, string until)
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", typed,
            "--until-screen", until,
            "--run", "500ms",
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
            .Select(line => line.Replace("\U0001FB2D", "").TrimEnd(' ', '\r'))
            .Where(line => line.Length > 0 && !IsDump(line)),
    ];

    private static bool IsDump(string line) =>
        line.Length > 5 && line[4] == ':' &&
        int.TryParse(line.AsSpan(0, 4), System.Globalization.NumberStyles.HexNumber, null, out _);
}
