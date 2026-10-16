using Cp500Os.C5fs;

namespace Cp500Os.EndToEnd.Tests;

public sealed class BootTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("cp500-os-e2e-").FullName;

    public static TheoryData<int> FloppySizes => [180, 360];

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    [Theory]
    [MemberData(nameof(FloppySizes))]
    public async Task StubRomLoadsTheBootSectorOfAC5fsFloppyTo4300hAndRunsIt(int sizeKiB)
    {
        byte[] bootSector = RepoPaths.ReadZ80Output("hello-boot.bin");
        string image = WriteBootableImage(sizeKiB, bootSector);

        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image,
            "--until-screen", "BOOT OK", "--timeout", "5s",
            "--dump-memory", $"4300:{bootSector.Length}");

        Assert.True(run.ExitCode == 0, run.Stderr);
        Assert.Equal(bootSector, run.DumpedMemory());
    }

    [Fact]
    public async Task StubRomReportsAnEmptyDriveOnScreen()
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--until-screen", "STUB ROM:", "--timeout", "10s", "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr);
        Assert.StartsWith("STUB ROM: RESTORE ERROR A4", run.Stdout, StringComparison.Ordinal);
    }

    [Theory]
    [MemberData(nameof(FloppySizes))]
    public async Task RealRomBootsTheSameImageAsTheStubRom(int sizeKiB)
    {
        string rom = Roms.RequireReal();
        byte[] bootSector = RepoPaths.ReadZ80Output("hello-boot.bin");
        string image = WriteBootableImage(sizeKiB, bootSector);

        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", rom, "--disk0", image,
            "--until-screen", "BOOT OK", "--timeout", "10s",
            "--dump-memory", $"4300:{bootSector.Length}");

        Assert.True(run.ExitCode == 0, run.Stderr);
        Assert.Equal(bootSector, run.DumpedMemory());
    }

    private string WriteBootableImage(int sizeKiB, byte[] bootSector)
    {
        VolumeGeometry geometry = sizeKiB == 180 ? VolumeGeometry.Floppy180 : VolumeGeometry.Floppy360;
        Volume volume = Volume.Format(new FormatOptions { Geometry = geometry, Label = "E2E", VolumeId = 0xC5000001 });
        volume.InstallBootSector(bootSector);
        Assert.Empty(volume.Check());

        string path = Path.Combine(_directory, $"boot-{sizeKiB}.dsk");
        File.WriteAllBytes(path, volume.ToImage());
        return path;
    }
}
