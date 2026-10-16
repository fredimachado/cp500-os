using static Cp500Os.C5fs.Tests.TestSupport;

namespace Cp500Os.C5fs.Tests;

public class SystemAreaTests
{
    [Fact]
    public void KernelIsOneContiguousRunRecordedInTheSuperblock()
    {
        Volume volume = Format360();
        byte[] kernel = Pattern(1000, 42);

        volume.InstallKernel(kernel);

        Assert.Equal(new Extent(22, 4), volume.Superblock.Kernel);
        Assert.Equal(2, volume.Stat("/sys").InodeNumber);
        FileStatus status = volume.Stat("/sys/kernel");
        Assert.Equal((3, 1000, "22-25"), (status.InodeNumber, status.Inode.Size, string.Join(",", status.Inode.Extents)));

        byte[] image = volume.ToImage();
        Assert.Equal([22, 0, 4, 0], Block(image, 1)[30..34].ToArray());
        Assert.Equal([22, 0, 4, 0], Block(image, 2)[30..34].ToArray());
        Assert.Equal(kernel, image.AsSpan(22 * 256, 1000).ToArray());
        Assert.False(image.AsSpan((22 * 256) + 1000, 24).ContainsAnyExcept((byte)0));
        Assert.Equal(kernel, Volume.Open(image).ReadFile("/sys/kernel"));
        AssertConsistent(volume);
    }

    [Fact]
    public void ReplacingTheKernelFreesTheOldRun()
    {
        Volume volume = Format360();
        volume.InstallKernel(Pattern(1000));
        volume.WriteFile("/after", Pattern(256));
        byte[] bigger = Pattern(2560, 7);

        volume.InstallKernel(bigger);

        Assert.Equal(new Extent(27, 10), volume.Superblock.Kernel);
        Assert.Equal(3, volume.Stat("/sys/kernel").InodeNumber);
        Assert.Equal(bigger, volume.ReadFile("/sys/kernel"));
        Assert.Equal(1419 - 1 - 1 - 10, volume.FreeBlocks);
        byte[] image = volume.ToImage();
        Assert.Equal([false, false, false, false, true], Enumerable.Range(22, 5).Select(block => IsBitSet(image, block)));
        Assert.Equal([27, 0, 10, 0], Block(image, 2)[30..34].ToArray());
        AssertConsistent(volume);
    }

    [Fact]
    public void KernelInstallFailsCleanlyWithoutAContiguousRun()
    {
        Volume volume = Format180();
        volume.WriteFile("/a", Pattern(350 * 256));
        volume.WriteFile("/s1", Pattern(256));
        volume.WriteFile("/b", Pattern((volume.FreeBlocks - 1) * 256));
        volume.WriteFile("/s2", Pattern(256));
        volume.Remove("/s1");
        volume.Remove("/s2");
        Assert.Equal(2, volume.FreeBlocks);
        byte[] before = volume.ToImage();

        C5fsException error = Assert.Throws<C5fsException>(() => volume.InstallKernel(Pattern(300)));

        Assert.Equal(C5fsError.ENOSPC, error.Error);
        Assert.Contains("2 contiguous", error.Message, StringComparison.Ordinal);
        Assert.Equal(before, volume.ToImage());
        Assert.Equal(C5fsError.ENOENT, ErrorOf(() => volume.Stat("/sys")));
        Assert.Null(volume.Superblock.Kernel);
        AssertConsistent(volume);
    }

    [Fact]
    public void KernelSizeIsLimitedToOneExtent()
    {
        Volume volume = Format360();

        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => volume.InstallKernel([])));
        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => volume.InstallKernel(new byte[(255 * 256) + 1])));
        volume.InstallKernel(Pattern(255 * 256));

        Assert.Equal(new Extent(22, 255), volume.Superblock.Kernel);
        AssertConsistent(volume);
    }

    [Fact]
    public void TheKernelFileIsOnlyWrittenThroughInstallKernel()
    {
        Volume volume = Format360();
        volume.CreateDirectory("/sys");

        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => volume.WriteFile("/sys/kernel", [1])));
        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => volume.WriteFile("/Sys/KERNEL", [1])));
        AssertConsistent(volume);
    }

    [Fact]
    public void RemovingTheKernelClearsTheSuperblockRun()
    {
        Volume volume = Format360();
        volume.InstallKernel(Pattern(600));

        volume.Remove("/sys/kernel");

        Assert.Null(volume.Superblock.Kernel);
        byte[] image = volume.ToImage();
        Assert.Equal([0, 0, 0, 0], Block(image, 2)[30..34].ToArray());
        Assert.False(IsBitSet(image, 22));
        AssertConsistent(volume);
    }

    [Fact]
    public void KernelNeedsSysToBeADirectory()
    {
        Volume volume = Format360();
        volume.WriteFile("/sys", [1]);

        Assert.Equal(C5fsError.ENOTDIR, ErrorOf(() => volume.InstallKernel([1])));
        AssertConsistent(volume);
    }

    [Fact]
    public void BootSectorLandsInBlockZeroPadded()
    {
        Volume volume = Format360();
        volume.InstallBootSector(Enumerable.Repeat((byte)0xC9, 256).ToArray());

        volume.InstallBootSector(Pattern(200));

        byte[] image = volume.ToImage();
        Assert.Equal(Pattern(200), image[..200]);
        Assert.False(image.AsSpan(200, 56).ContainsAnyExcept((byte)0));
        Assert.Equal("C5FS"u8.ToArray(), image[256..260]);
        AssertConsistent(volume);
    }

    [Fact]
    public void BootSectorMustFitOneBlock()
    {
        Volume volume = Format360();

        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => volume.InstallBootSector(new byte[257])));
        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => volume.InstallBootSector([])));
    }

    [Fact]
    public void InstallingABootSectorIsAMutatingSession()
    {
        Volume volume = Volume.Open(Format360().ToImage());

        volume.InstallBootSector([0xC3, 0x00, 0x42]);

        byte[] image = volume.ToImage();
        Assert.Equal([0xC3, 0x00, 0x42, 0x00], image[..4]);
        Assert.Equal(2, Volume.Open(image).Superblock.Generation);
    }
}
