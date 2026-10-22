using System.Globalization;
using Cp500Os.C5fs;

namespace Cp500Os.EndToEnd.Tests;

public sealed class DeviceTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("cp500-os-dev-").FullName;

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    [Fact]
    public async Task NullDiscardsAWrite()
    {
        RunResult run = await RunProduct("/lib/devtest.c5x n", "ok");
        AssertOk(run);
    }

    [Fact]
    public async Task ConsoleIsANewDescriptor()
    {
        RunResult run = await RunProduct("/lib/devtest.c5x c", "ok");
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, line => line.Contains('C'));
        Assert.Contains(lines, line => line.Contains("ok"));
        Assert.DoesNotContain(lines, line => line.StartsWith("exit ", StringComparison.Ordinal));
    }

    [Fact]
    public async Task PrinterReadDoesNotHang()
    {
        RunResult run = await RunProduct("/lib/devtest.c5x p", "done");
        Assert.Contains(Visible(run.Stdout), line => line.Contains("done"));
    }

    [Fact]
    public async Task MissingFloppyIsEnodev()
    {
        RunResult run = await RunProduct("/lib/devtest.c5x f", "exit 18");
        Assert.Contains(Visible(run.Stdout), line => line == "exit 18");
    }

    [Fact]
    public async Task StartupScriptPrintsBeforeThePrompt()
    {
        string image = CopyImage();
        Volume volume = Volume.Open(File.ReadAllBytes(image));
        volume.WriteFile("/etc/rc", File.ReadAllBytes(Path.Combine(RepoPaths.Root, "build", "z80", "rcprint.c5x")));
        File.WriteAllBytes(image, volume.ToImage());

        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image,
            "--until-screen", "rc", "--timeout", "20s",
            "--until-screen", "sh>",
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        int rc = Array.FindIndex(lines, line => line.Contains("rc"));
        int prompt = Array.FindIndex(lines, line => line.Contains("sh>"));
        Assert.True(rc >= 0 && prompt > rc);
    }

    [Fact]
    public async Task TmpIsEmptyAfterBoot()
    {
        string image = CopyImage();
        Volume volume = Volume.Open(File.ReadAllBytes(image));
        volume.CreateDirectory("/tmp");
        volume.WriteFile("/tmp/stale", "gone"u8.ToArray());
        File.WriteAllBytes(image, volume.ToImage());

        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image,
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", "/bin/ls /tmp{ENTER}",
            "--until-screen", "sh>",
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.DoesNotContain(Visible(run.Stdout), line => line.Contains("stale"));
    }

    private static async Task<RunResult> RunProduct(string command, string until)
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

    private string CopyImage()
    {
        string path = Path.Combine(_directory, "disk.dsk");
        File.Copy(Product(), path);
        return path;
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
