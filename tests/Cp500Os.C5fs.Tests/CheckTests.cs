using System.Buffers.Binary;
using static Cp500Os.C5fs.Tests.TestSupport;

namespace Cp500Os.C5fs.Tests;

public class CheckTests
{
    [Fact]
    public void ALeakedBlockIsReported()
    {
        byte[] image = Format360().ToImage();
        image[(3 * 256) + 100] |= 0x01;

        Assert.Equal(["block 800 is marked used but nothing owns it"], Volume.Open(image).Check());
    }

    [Fact]
    public void AnOwnedBlockMarkedFreeIsReported()
    {
        Volume volume = Format360();
        volume.WriteFile("/f", [1]);
        byte[] image = volume.ToImage();
        image[(3 * 256) + 2] &= unchecked((byte)~(1 << 5));

        Assert.Equal(["block 21 is owned by inode 2 but marked free"], Volume.Open(image).Check());
    }

    [Fact]
    public void ABlockOwnedTwiceIsReported()
    {
        Volume volume = Format360();
        volume.WriteFile("/a", [1]);
        volume.WriteFile("/b", [2]);
        byte[] image = volume.ToImage();
        BinaryPrimitives.WriteUInt16LittleEndian(Block(image, 4)[((3 * 32) + 13)..], 21);

        Assert.Equal(
            ["block 21 is owned by both inode 2 and inode 3", "block 22 is marked used but nothing owns it"],
            Volume.Open(image).Check());
    }

    [Fact]
    public void DuplicateFoldedNamesAreReported()
    {
        Volume volume = Format360();
        volume.WriteFile("/a", [1]);
        volume.WriteFile("/b", [2]);
        byte[] image = volume.ToImage();
        Block(image, 20)[66] = (byte)'A';

        Assert.Equal(["directory '/': duplicate name 'A' (names compare case-insensitively)"], Volume.Open(image).Check());
    }

    [Fact]
    public void AWrongDotDotIsReported()
    {
        Volume volume = Format360();
        volume.CreateDirectory("/d");
        byte[] image = volume.ToImage();
        Block(image, 21)[0] = 2;

        Assert.Equal(["directory '/d': the first entry must be '..' pointing at inode 1"], Volume.Open(image).Check());
    }

    [Fact]
    public void AnOrphanInodeIsReported()
    {
        Volume volume = Format360();
        volume.WriteFile("/a", [1]);
        byte[] image = volume.ToImage();
        Block(image, 20)[32..64].Clear();

        Assert.Equal(["inode 2 is allocated but no directory entry points at it"], Volume.Open(image).Check());
    }

    [Fact]
    public void ASizeThatDoesNotFitItsExtentsIsReported()
    {
        Volume volume = Format360();
        volume.WriteFile("/a", [1]);
        byte[] image = volume.ToImage();
        Block(image, 4)[(2 * 32) + 3] = 0x02;

        Volume opened = Volume.Open(image);
        string problem = Assert.Single(opened.Check(), p => p.StartsWith("inode 2:", StringComparison.Ordinal));
        Assert.Contains("513 bytes need 3 blocks", problem, StringComparison.Ordinal);
        Assert.Equal(C5fsError.EIO, ErrorOf(() => opened.Stat("/a")));
    }

    [Fact]
    public void AKernelRunThatDoesNotMatchTheFileIsReported()
    {
        Volume volume = Format360();
        volume.InstallKernel(Pattern(1000));
        byte[] image = volume.ToImage();
        Superblock moved = Superblock.Parse(Block(image, 2)) with { Kernel = new Extent(30, 4) };
        moved.Serialize().CopyTo(Block(image, 2));

        Assert.Equal(
            ["the superblock kernel run 30-33 does not match /sys/kernel's extents 22-25"],
            Volume.Open(image).Check());
    }
}
