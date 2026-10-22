using System.Globalization;

namespace Cp500Os.EndToEnd.Tests;

/// <summary>Background jobs, kill, ps and the task names SYS_TASKINFO reports.</summary>
public sealed class TaskTests
{
    // Slot 0 is init, slot 1 the shell, so the first background job takes slot 2. Its name is
    // TASK_NAMES (C308h) + 8 * 2 = C318h.
    private const string Slot2NameAddress = "C318";

    [Fact]
    public async Task BackgroundPrintsTaskId()
    {
        RunResult run = await TypeAsync("? /lib/spin.c5x{ENTER}", "ok 2");
        Assert.Contains(Visible(run.Stdout), line => line == "ok 2");
    }

    [Fact]
    public async Task KillEndsBackgroundJob()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "? /lib/spin.c5x{ENTER}", "--until-screen", "ok 2",
            "--type", "kill 2{ENTER}", "--run", "1s",
            "--type", string.Concat(Enumerable.Repeat("? /bin/hi{ENTER}", 6)), "--run", "1s",
            "--type", "/bin/hi{ENTER}", "--until-screen", "exit 3",
            "--type", "ps{ENTER}", "--run", "1s",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line == "exit 3");
        PsRow[] rows = PsRows(lines);
        Assert.Contains(rows, row => row.Name == "ps");
        Assert.DoesNotContain(rows, row => row.Name == "spin");
    }

    [Fact]
    public async Task KillRefusesShell()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "kill 1{ENTER}", "--until-screen", "EBUSY",
            "--type", "/bin/hi{ENTER}", "--until-screen", "exit 3",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line == "EBUSY");
        Assert.Contains(lines, line => line == "exit 3");
    }

    [Fact]
    public async Task KillBadIdIsEinval()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "kill 9{ENTER}", "--until-screen", "EINVAL",
            "--type", "kill 5{ENTER}", "--run", "1s",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Equal(2, Visible(run.Stdout).Count(line => line == "EINVAL"));
    }

    [Fact]
    public async Task PsListsTasks()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "? /lib/spin.c5x{ENTER}", "--until-screen", "ok 2",
            "--type", "ps{ENTER}", "--run", "1s",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        PsRow[] rows = PsRows(Visible(run.Stdout));
        Assert.Contains(rows, row => row.Name == "init");
        Assert.Contains(rows, row => row.Name == "sh");
        Assert.Contains(rows, row => row.Name == "spin" && row.State == 'R');
        Assert.Contains(rows, row => row.Name == "ps");
    }

    [Fact]
    public async Task PsShowsBlockedChannel()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "? /bin/cat{ENTER}", "--until-screen", "ok 2",
            "--type", "ps{ENTER}", "--run", "1s",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        PsRow cat = Assert.Single(PsRows(Visible(run.Stdout)), row => row.Name == "cat");
        Assert.Equal('B', cat.State);
        Assert.Equal("key", cat.Wait);
    }

    [Fact]
    public async Task SpawnNameUsesBasename()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "? /lib/spin.c5x{ENTER}", "--until-screen", "ok 2",
            "--dump-memory", $"{Slot2NameAddress}:8");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Equal("spin\0\0\0\0"u8.ToArray(), run.DumpedMemory());
    }

    private sealed record PsRow(int Id, char State, string Wait, string Name);

    /// <summary>
    /// Rows of ps output: ID in columns 0-1, ST at 3, WAIT at 6-10, PPID at 12-15, MEM at 17-20,
    /// CON at 23, NAME from 26. The header and the echoed command line are not rows.
    /// </summary>
    private static PsRow[] PsRows(string[] lines)
    {
        var rows = new List<PsRow>();
        foreach (string line in lines)
        {
            if (line.Length < 27 || !char.IsDigit(line[1]) || line[2] != ' ')
                continue;

            int id = int.Parse(line[..2].Trim(), CultureInfo.InvariantCulture);
            rows.Add(new PsRow(id, line[3], line[6..11].Trim(), line[26..].Trim()));
        }

        return [.. rows];
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
