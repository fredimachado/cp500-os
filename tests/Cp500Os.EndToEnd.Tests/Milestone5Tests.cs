using System.Globalization;
using Cp500Os.C5x;

namespace Cp500Os.EndToEnd.Tests;

public sealed class Milestone5Tests
{
    [Fact]
    public async Task BackgroundSpinnerLeavesTheShellResponsive()
    {
        RunResult run = await TypeAsync("? /lib/reloc.c5x{ENTER}/bin/hi{ENTER}", "exit 3");
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line == "hello");
        Assert.Contains(lines, line => line == "exit 3");
    }

    [Fact]
    public async Task SecondBackgroundSpawnIsNotBusy()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "? /lib/reloc.c5x{ENTER}? /lib/reloc.c5x{ENTER}",
            "--run", "2s",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Equal(2, lines.Count(line => line == "ok"));
        Assert.DoesNotContain(lines, line => line == "EBUSY");
    }

    [Fact]
    public async Task PipeCarriesCatIntoCatUntilEndOfFile()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "/bin/cat /home/note ! /bin/cat{ENTER}", "--until-screen", "hello",
            "--type", "/bin/hi ! /bin/cat{ENTER}", "--until-screen", "c5fs-ok",
            "--type", "/bin/ls /home{ENTER}", "--until-screen", "lines",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line == "lines");
        Assert.DoesNotContain(lines, line => line == "exit 3");
    }

    [Fact]
    public async Task ClearTwoShowsASecondShellAndClearOneRestoresTheFirst()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "{CLEAR}2", "--until-screen", "sh>",
            "--type", "/bin/hi{ENTER}", "--until-screen", "exit 3",
            "--type", "{CLEAR}1", "--until-screen", "cp500-os/",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line == "cp500-os/");
        Assert.Contains(lines, line => line == "XX");
        Assert.DoesNotContain(lines, line => line == "exit 3");
    }

    [Fact]
    public async Task BreakEndsTheForegroundProgram()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "/lib/reloc.c5x{ENTER}",
            "--run", "2s",
            "--type", "{BREAK}", "--until-screen", "exit 255",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Contains(Visible(run.Stdout), line => line == "exit 255");
    }

    [Fact]
    public async Task BreakAtThePromptKeepsTheShell()
    {
        RunResult run = await TypeAsync("{BREAK}/bin/hi{ENTER}", "exit 3");
        Assert.Contains(Visible(run.Stdout), line => line == "exit 3");
    }

    [Fact]
    public async Task RawModeDeliversBreakAsCode3()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "/lib/rawkey.c5x{ENTER}", "--until-screen", "ready",
            "--type", "{BREAK}", "--until-screen", "exit 3",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Contains(Visible(run.Stdout), line => line == "exit 3");
    }

    [Fact]
    public async Task AcuteDeadKeyComposesAndFallsBack()
    {
        RunResult run = await TypeAsync("'a'e'i'C", "áéiÇ");
        Assert.Contains(Visible(run.Stdout), line => line == "áéiÇ");
    }

    [Fact]
    public async Task ApostropheThenSpaceIsAnApostrophe()
    {
        RunResult run = await TypeAsync("' x", "'x");
        Assert.Contains(Visible(run.Stdout), line => line == "'x");
    }

    [Fact]
    public async Task RoundRobinLetsBothReadyChildrenMakeProgress()
    {
        int shellPages = Load("sh.c5x").Header.MemoryPages;
        int spinPages = Load("spin.c5x").Header.MemoryPages;
        int first = 0x62 + shellPages;
        int second = first + spinPages;
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "? /lib/spin.c5x{ENTER}? /lib/spin.c5x{ENTER}/bin/hi{ENTER}",
            "--until-screen", "exit 3",
            "--dump-memory", $"{first * 256 + 2:X4}:4",
            "--dump-memory", $"{second * 256 + 2:X4}:4");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        byte[] counts = run.DumpedMemory();
        Assert.NotEqual(0u, BitConverter.ToUInt32(counts, 0));
        Assert.NotEqual(0u, BitConverter.ToUInt32(counts, 4));
    }

    [Fact]
    public async Task TickDuringASyscallDefersTheSwitchUntilReturn()
    {
        int child = 0x62 + Load("sh.c5x").Header.MemoryPages;
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "30s",
            "--type", "? /lib/statloop.c5x{ENTER}/bin/hi{ENTER}",
            "--until-screen", "exit 3",
            "--dump-screen",
            "--dump-memory", $"{child * 256 + 2:X4}:2");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        foreach (string expected in new[] { "hello", "c5fs-ok", "bin", "EROFS", "/", "/bin", "ENOTDIR", "ok", "exit 3" })
            Assert.Contains(lines, line => line == expected);
        Assert.DoesNotContain(lines, line => line == "BAD");
        Assert.NotEqual(0, BitConverter.ToUInt16(run.DumpedMemory(), 0));
    }

    [Fact]
    public async Task PromptReapsBackgroundZombies()
    {
        RunResult run = await TypeAsync(
            string.Concat(Enumerable.Repeat("? /bin/hi{ENTER}", 7)) + "/bin/hi{ENTER}", "exit 3");
        Assert.Contains(Visible(run.Stdout), line => line == "exit 3");
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
