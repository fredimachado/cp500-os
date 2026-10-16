using Cp500Os.C5fs;

namespace Cp500Os.EndToEnd.Tests;

public sealed class Milestone2Tests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("cp500-os-m2-").FullName;

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    [Fact]
    public void TickSymbolIs4015h()
    {
        string sym = File.ReadAllText(RepoPaths.Z80Output("kernel.sym"));
        Assert.Contains("TICK_COUNT: EQU 0x00004015", sym, StringComparison.Ordinal);
    }

    [Fact]
    public async Task StubRomShowsTheBanner()
    {
        RunResult run = await BootAsync(Roms.Stub, ProductImage(), "10s");
        AssertBanner(run);
    }

    [Fact]
    public async Task StubRomEchoesTypedText()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", ProductImage(),
            "--until-screen", "cp500-os/", "--timeout", "10s",
            "--type", "Hi", "--until-screen", "Hi",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Contains(run.Stdout.Split('\n'), line => line == "Hi" || line.StartsWith("Hi", StringComparison.Ordinal));
        AssertBanner(run);
    }

    [Fact]
    public async Task RightArrowMovesTheCursorBeforeTheNextGlyph()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", ProductImage(),
            "--until-screen", "cp500-os/", "--timeout", "10s",
            "--type", "{RIGHT}Z", "--until-screen", "Z",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.Contains(run.Stdout.Split('\n'), static line => line.StartsWith(" Z", StringComparison.Ordinal));
    }

    [Fact]
    public async Task BreakDoesNotChangeTheBanner()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", ProductImage(),
            "--until-screen", "cp500-os/", "--timeout", "10s",
            "--type", "{BREAK}", "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        AssertBanner(run);
        Assert.DoesNotContain(run.Stdout.Split('\n'), static line => line.Contains("STALE", StringComparison.Ordinal));
    }

    [Fact]
    public async Task TickCounterAdvancesThirtyCountsPerSecond()
    {
        uint first = await TicksAfter("999.9901ms");
        uint second = await TicksAfter("1999.9802ms");
        Assert.Equal(first + 30u, second);
        Assert.Equal(0u, first >> 16);
    }

    [Fact]
    public async Task Floppy180BootsTheSameBanner()
    {
        string image = ImageWithKernel(180, RepoPaths.ReadZ80Output("boot.bin"), RepoPaths.ReadZ80Output("kernel.bin"));
        RunResult run = await BootAsync(Roms.Stub, image, "10s");
        AssertBanner(run);
    }

    [Fact]
    public async Task StaleSuperblockADoesNotBoot()
    {
        string image = ImageWithStaleCopyA();
        RunResult run = await BootAsync(Roms.Stub, image, "15s");
        AssertBanner(run);
        Assert.DoesNotContain("STALE", run.Stdout, StringComparison.Ordinal);
    }

    [Fact]
    public async Task MissingKernelHaltsWithK()
    {
        string image = Path.Combine(_directory, "no-kernel.dsk");
        Volume volume = Volume.Format(new FormatOptions { Geometry = VolumeGeometry.Floppy360, Label = "NONE" });
        volume.InstallBootSector(RepoPaths.ReadZ80Output("boot.bin"));
        File.WriteAllBytes(image, volume.ToImage());

        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image,
            "--until-screen", "K", "--timeout", "10s", "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.StartsWith("K", run.Stdout, StringComparison.Ordinal);
    }

    [Fact]
    public void ProductImageKeepsTheKernelOnlyInTheNewerSuperblock()
    {
        byte[] image = File.ReadAllBytes(ProductImage());
        uint sequenceA = BitConverter.ToUInt32(image, 256 + 6);
        uint sequenceB = BitConverter.ToUInt32(image, 512 + 6);
        Assert.True(sequenceA > sequenceB);
        Assert.Equal(0u, BitConverter.ToUInt32(image, 512 + 30));
        Assert.NotEqual((ushort)0, BitConverter.ToUInt16(image, 256 + 32));
    }

    [Fact]
    public async Task RealRomShowsTheBanner()
    {
        string rom = Roms.RequireReal();
        RunResult run = await BootAsync(rom, ProductImage(), "20s");
        AssertBanner(run);
    }

    private static async Task<uint> TicksAfter(string duration)
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", ProductImage(),
            "--until-screen", "cp500-os/", "--timeout", "10s",
            "--run", duration, "--dump-memory", "4015:4");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        byte[] ticks = run.DumpedMemory();
        Assert.Equal(4, ticks.Length);
        return BitConverter.ToUInt32(ticks);
    }

    private static async Task<RunResult> BootAsync(string rom, string image, string timeout)
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", rom, "--disk0", image,
            "--until-screen", "cp500-os/", "--timeout", timeout,
            "--until-screen", "XX", "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        return run;
    }

    private static void AssertBanner(RunResult run)
    {
        string[] lines = run.Stdout.Split('\n');
        Assert.Contains(lines, static line => line == "cp500-os/");
        Assert.Contains(lines, static line => line == "XX");
        Assert.DoesNotContain(lines, static line => line.Contains("XXXX", StringComparison.Ordinal));
    }

    private static string ProductImage() => Path.Combine(RepoPaths.Root, "build", "cp500-os.dsk");

    private string ImageWithKernel(int sizeKiB, byte[] boot, byte[] kernel)
    {
        VolumeGeometry geometry = sizeKiB == 180 ? VolumeGeometry.Floppy180 : VolumeGeometry.Floppy360;
        Volume volume = Volume.Format(new FormatOptions { Geometry = geometry, Label = "CP500" });
        volume.InstallBootSector(boot);
        volume.InstallKernel(kernel);
        string path = Path.Combine(_directory, $"os-{sizeKiB}.dsk");
        File.WriteAllBytes(path, volume.ToImage());
        return path;
    }

    private string ImageWithStaleCopyA()
    {
        byte[] boot = RepoPaths.ReadZ80Output("boot.bin");
        byte[] kernel = RepoPaths.ReadZ80Output("kernel.bin");
        string path = ImageWithKernel(360, boot, kernel);
        byte[] image = File.ReadAllBytes(path);

        byte[] decoy =
        [
            0x21, 0x0D, 0x42,
            0x11, 0x00, 0x3C,
            0x01, 0x05, 0x00,
            0xED, 0xB0,
            0xF3,
            0x76,
            (byte)'S', (byte)'T', (byte)'A', (byte)'L', (byte)'E',
        ];
        decoy.CopyTo(image, 100 * 256);

        Span<byte> copyA = image.AsSpan(256, 256);
        BitConverter.TryWriteBytes(copyA[30..], (ushort)100);
        BitConverter.TryWriteBytes(copyA[32..], (ushort)1);
        ushort crc = Crc16Ccitt.Compute(copyA[..254]);
        BitConverter.TryWriteBytes(copyA[254..], crc);
        File.WriteAllBytes(path, image);
        return path;
    }
}
