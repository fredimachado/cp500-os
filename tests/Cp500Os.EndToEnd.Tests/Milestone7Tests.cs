using System.Diagnostics;
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
    public async Task Hd0ReadsThePartitionTable()
    {
        HardDiskBoard.Require();
        Volume one = PartitionVolume(400, [("/x", PartitionPattern(400))]);
        Volume two = PartitionVolume(400, [("/only2", [0x2A])]);
        string hd = WriteHd([one, two, null, null]);
        RunResult run = await RunWithHdAsync(hd,
            "/bin/cat /mnt/hd0p1/x{ENTER}",
            "--run", "3s",
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.DoesNotContain(Visible(run.Stdout), line => line.StartsWith("exit ", StringComparison.Ordinal));

        RunResult enoent = await RunFixtureWithHdAsync(hd, "/lib/hdtest.c5x n", "exit 1");
        AssertExit(enoent, 1);
        RunResult empty = await RunFixtureWithHdAsync(hd, "/lib/hdtest.c5x 3", "exit 1");
        AssertExit(empty, 1);

        RunResult hide = await RunWithHdAsync(hd,
            "/bin/cat /mnt/hd0p1/only2{ENTER}",
            "--run", "2s",
            "--dump-screen");
        Assert.DoesNotContain(Visible(hide.Stdout), line => line == "*");
    }

    [Fact]
    public async Task PartitionFileReadsSeeksAndStats()
    {
        HardDiskBoard.Require();
        Volume part = PartitionVolume(400, [("/x", PartitionPattern(2048))]);
        string hd = WriteHd([part, null, null, null]);
        RunResult run = await RunFixtureWithHdAsync(hd, "/lib/hdtest.c5x f", "exit 44");
        AssertExit(run, 44);
    }

    [Fact]
    public async Task SecondFloppyReadsAndWritesAfterRootAccess()
    {
        string first = ProductCopy("cp500-fd0");
        string second = ProductCopy("cp500-fd1");
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", first, "--disk1", second, "--write-back", "--timeout", "40s",
            "--until-screen", "sh>",
            "--type", "/bin/ls /home{ENTER}/bin/cat /mnt/fd1/home/note{ENTER}/bin/cp /bin/date /mnt/fd1/home/d{ENTER}",
            "--run", "8s",
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Contains("hello", Visible(run.Stdout));
        Assert.DoesNotContain(Visible(run.Stdout), line => line.StartsWith("exit ", StringComparison.Ordinal));
        byte[] expected = Volume.Open(File.ReadAllBytes(Product())).ReadFile("/bin/date");
        Assert.Equal(expected, Volume.Open(File.ReadAllBytes(second)).ReadFile("/home/d"));
    }

    [Fact]
    public async Task PartitionWriteReadsBackOnTheHost()
    {
        HardDiskBoard.Require();
        Volume part = PartitionVolume(400, []);
        string hd = WriteHd([part, null, null, null]);
        string disk = ProductCopy("cp500-fd0");
        RunResult run = await HeadlessRunner.RunAsync([
            "--rom", Roms.Stub, "--disk0", disk, .. HdArgs(hd), "--write-back", "--timeout", "40s",
            "--until-screen", "sh>",
            "--type", "/bin/cp /home/note /mnt/hd0p1/note{ENTER}",
            "--run", "5s",
            "--dump-screen"]);
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        byte[] expected = Volume.Open(File.ReadAllBytes(disk)).ReadFile("/home/note");
        byte[] actual = HardDisk.OpenPartition(File.ReadAllBytes(hd), 1).ReadFile("/note");
        Assert.Equal(expected, actual);
    }

    [Fact]
    public async Task LargePartitionRefusesWrites()
    {
        HardDiskBoard.Require();
        Volume small = PartitionVolume(400, []);
        Volume huge = PartitionVolume(4096, []);
        string hd = WriteHd([small, huge, null, null]);
        RunResult run = await RunFixtureWithHdAsync(hd, "/lib/hdtest.c5x w", "exit 7");
        AssertExit(run, 7);
        RunResult root = await RunFixtureWithHdAsync(hd, "/lib/hdtest.c5x r", "exit 42");
        AssertExit(root, 42);
    }

    [Fact]
    public async Task BadSuperblockIsEioAndRootSurvives()
    {
        HardDiskBoard.Require();
        Volume part = PartitionVolume(400, [("/x", [1])]);
        byte[] hdBytes = HardDisk.Build([part, null, null, null]);
        hdBytes[512 + 254] ^= 0xFF;
        hdBytes[768 + 254] ^= 0xFF;
        string hd = WriteHdBytes(hdBytes);
        RunResult fail = await RunFixtureWithHdAsync(hd, "/lib/hdtest.c5x m", "exit 7");
        AssertExit(fail, 7);
        RunResult root = await RunFixtureWithHdAsync(hd, "/lib/hdtest.c5x r", "exit 42");
        AssertExit(root, 42);
    }

    [Fact]
    public async Task ClockComesFromTheBoard()
    {
        HardDiskBoard.Require();
        Volume part = PartitionVolume(200, []);
        string hd = WriteHd([part, null, null, null]);
        // The emulated board clock reads the host's local time.
        uint before = C5Time.Now(TimeProvider.System).Seconds;
        RunResult run = await HeadlessRunner.RunAsync([
            "--rom", Roms.Stub, "--disk0", Product(), .. HdArgs(hd), "--timeout", "40s",
            "--until-screen", "sh>",
            "--type", "/bin/date{ENTER}",
            "--run", "3s",
            "--dump-memory", "F7F0:8",
            "--dump-memory", $"{ClockBase():X4}:8",
            "--dump-screen"]);
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        byte[] memory = run.DumpedMemory();
        uint seconds = BitConverter.ToUInt32(memory, 4);
        uint origin = BitConverter.ToUInt32(memory, 8);
        // The board advances with emulated time, which outruns the wall clock on a busy host.
        Assert.InRange(origin, before - 2, C5Time.Now(TimeProvider.System).Seconds + 40);
        Assert.Contains(Visible(run.Stdout), line => line == new C5Time(seconds).ToString());
    }

    [Fact]
    public async Task HaltedBoardClockKeepsRootTime()
    {
        HardDiskBoard.Require();
        if (!HardDiskBoard.CanHaltClock())
            Assert.Skip("pinned heh8080 cannot halt the FreHD clock");

        Volume part = PartitionVolume(200, []);
        string hd = WriteHd([part, null, null, null]);
        string image = Product();
        uint lastWritten = Volume.Open(File.ReadAllBytes(image)).Superblock.LastWritten.Seconds;
        RunResult halt = await HeadlessRunner.RunAsync([
            "--rom", Roms.Stub, "--disk0", image, .. HdArgs(hd), "--hd-halt", "--timeout", "40s",
            "--until-screen", "sh>",
            "--type", "/bin/date{ENTER}",
            "--run", "3s",
            "--dump-memory", "F7F0:8",
            "--dump-memory", $"{ClockBase():X4}:8",
            "--dump-screen"]);
        Assert.True(halt.ExitCode == 0, halt.Stderr + halt.Stdout);
        byte[] memory = halt.DumpedMemory();
        uint origin = BitConverter.ToUInt32(memory, 8);
        Assert.Equal(lastWritten, origin);
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

    private static async Task<RunResult> RunFixtureWithHdAsync(string hd, string command, string until) =>
        await RunWithHdAsync(hd,
            command + "{ENTER}",
            "--until-screen", until,
            "--dump-screen");

    private static async Task<RunResult> RunWithHdAsync(string hd, params string[] extra)
    {
        RunResult run = await HeadlessRunner.RunAsync([
            "--rom", Roms.Stub, "--disk0", Product(), .. HdArgs(hd), "--timeout", "40s",
            "--until-screen", "sh>",
            "--type",
            .. extra,
        ]);
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        return run;
    }

    private static void AssertExit(RunResult run, int code)
    {
        Assert.Contains(Visible(run.Stdout), line => line == $"exit {code}");
    }

    private static Volume PartitionVolume(int blocks, IReadOnlyList<(string Path, byte[] Content)> files)
    {
        Volume volume = Volume.Format(new FormatOptions { Geometry = VolumeGeometry.Partition(blocks, 128) });
        foreach ((string path, byte[] content) in files)
            volume.WriteFile(path, content);

        return volume;
    }

    private static byte[] PartitionPattern(int length)
    {
        byte[] bytes = new byte[length];
        for (int i = 0; i < length; i++)
            bytes[i] = (byte)(i ^ (i >> 8));

        return bytes;
    }

    private static string WriteHd(IReadOnlyList<Volume?> parts) => WriteHdBytes(HardDisk.Build(parts));

    /// <summary>The kernel addresses the FreHD as 8 heads of 32 sectors, so images are whole cylinders.</summary>
    private const int CylinderBytes = 8 * 32 * VolumeGeometry.BlockSize;

    private static string[] HdArgs(string hd) =>
        ["--hard-disk", hd, "--chs", $"{new FileInfo(hd).Length / CylinderBytes},8,32"];

    private static string WriteHdBytes(byte[] bytes)
    {
        string path = Path.Combine(Path.GetTempPath(), $"cp500-hd-{Guid.NewGuid():N}.img");
        Array.Resize(ref bytes, (bytes.Length + CylinderBytes - 1) / CylinderBytes * CylinderBytes);
        File.WriteAllBytes(path, bytes);
        return path;
    }

    private static ushort ClockBase()
    {
        string sym = File.ReadAllText(Path.Combine(RepoPaths.Root, "build", "z80", "kernel.sym"));
        int mark = sym.IndexOf("clk_base: EQU 0x", StringComparison.Ordinal);
        Assert.True(mark >= 0);
        return ushort.Parse(sym.AsSpan(mark + "clk_base: EQU 0x".Length, 8), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }

    /// <summary>A private copy for a run that writes back, so the shared product image stays as built.</summary>
    private static string ProductCopy(string prefix)
    {
        string path = Path.Combine(Path.GetTempPath(), $"{prefix}-{Guid.NewGuid():N}.dsk");
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

internal static class HardDiskBoard
{
    private static string? _help;

    public static void Require()
    {
        if (Help().Contains("--hard-disk", StringComparison.Ordinal))
            return;

        Assert.Skip("pinned heh8080 has no hard disk; mounted-partition path was not run");
    }

    public static bool CanHaltClock() => Help().Contains("--hd-halt", StringComparison.Ordinal);

    private static string Help() => _help ??= ReadHelp();

    private static string ReadHelp()
    {
        string exe = Path.Combine(AppContext.BaseDirectory, OperatingSystem.IsWindows() ? "heh8080-cp500.exe" : "heh8080-cp500");
        var startInfo = new ProcessStartInfo(exe)
        {
            RedirectStandardOutput = true,
            UseShellExecute = false,
            ArgumentList = { "--help" },
        };
        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Could not start runner.");
        string text = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        return text;
    }
}
