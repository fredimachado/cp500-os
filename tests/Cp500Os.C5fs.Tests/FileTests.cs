using System.Buffers.Binary;
using static Cp500Os.C5fs.Tests.TestSupport;

namespace Cp500Os.C5fs.Tests;

public class FileTests
{
    [Theory]
    [InlineData(0, "")]
    [InlineData(1, "21")]
    [InlineData(256, "21")]
    [InlineData(257, "21-22")]
    [InlineData(100_000, "21-275,276-411")]
    public void WriteAndReadRoundTrip(int size, string expectedExtents)
    {
        Volume volume = Format360();
        byte[] content = Pattern(size);

        volume.WriteFile("/data.bin", content);

        Assert.Equal(content, volume.ReadFile("/data.bin"));
        FileStatus status = volume.Stat("/data.bin");
        Assert.Equal(2, status.InodeNumber);
        Assert.Equal(InodeKind.File, status.Inode.Kind);
        Assert.Equal(size, status.Inode.Size);
        Assert.Equal(expectedExtents, string.Join(",", status.Inode.Extents));
        Assert.Equal(1419 - Inode.BlocksFor(size), volume.FreeBlocks);

        byte[] image = volume.ToImage();
        Assert.Equal(content, Volume.Open(image).ReadFile("/DATA.BIN"));
        AssertConsistent(volume);
    }

    [Fact]
    public void InodeBytesAreLittleEndianWithA24BitSize()
    {
        Volume volume = Format360();
        volume.WriteFile("/f", Pattern(100_000));

        Span<byte> slot = Block(volume.ToImage(), 4)[64..96];

        Assert.Equal(
            [0x01, 0x02, 0xA0, 0x86, 0x01, 0xA0, 0x4F, 0x03, 0x58, 0xA0, 0x4F, 0x03, 0x58,
             0x15, 0x00, 0xFF, 0x14, 0x01, 0x88],
            slot[..19].ToArray());
        Assert.False(slot[19..].ContainsAnyExcept((byte)0));
    }

    [Fact]
    public void AllocationTakesTheFirstRunThatHoldsTheWholeFile()
    {
        Volume volume = Format360();
        volume.WriteFile("/a", Pattern(256));
        volume.WriteFile("/b", Pattern(256));
        volume.Remove("/a");

        volume.WriteFile("/c", Pattern(1000));
        volume.WriteFile("/d", Pattern(1));

        Assert.Equal("23-26", string.Join(",", volume.Stat("/c").Inode.Extents));
        Assert.Equal("21", string.Join(",", volume.Stat("/d").Inode.Extents));
        AssertConsistent(volume);
    }

    [Fact]
    public void LastBlockTailIsZeroed()
    {
        Volume volume = Format360();
        volume.WriteFile("/big", Enumerable.Repeat((byte)0xEE, 512).ToArray());
        volume.Remove("/big");

        volume.WriteFile("/small", [0x42]);

        byte[] image = volume.ToImage();
        Assert.Equal(0x42, Block(image, 21)[0]);
        Assert.False(Block(image, 21)[1..].ContainsAnyExcept((byte)0));
    }

    [Fact]
    public void FragmentedFreeSpaceSpillsExtentsIntoAnIndirectBlock()
    {
        Volume volume = Format360();
        for (int i = 0; i < 20; i++)
        {
            volume.WriteFile($"/f{i:00}", Pattern(4 * 256, i));
        }

        volume.WriteFile("/filler", Pattern(volume.FreeBlocks * 256));
        for (int i = 0; i < 20; i += 2)
        {
            volume.Remove($"/f{i:00}");
        }

        Assert.Equal(40, volume.FreeBlocks);
        byte[] content = Pattern((29 * 256) - 100, 99);

        volume.WriteFile("/fragmented", content);

        Inode inode = volume.Stat("/fragmented").Inode;
        Assert.Equal([4, 4, 4, 4, 4, 4, 4, 1], inode.Extents.Select(extent => (int)extent.Length));
        Assert.True(inode.NeedsIndirectBlock);
        Assert.Equal(10, volume.FreeBlocks);
        Assert.Equal(content, volume.ReadFile("/fragmented"));

        ushort number = volume.Stat("/fragmented").InodeNumber;
        byte[] image = volume.ToImage();
        Span<byte> slot = Block(image, 4 + (number / 8)).Slice(number % 8 * 32, 32);
        Assert.Equal(0x41, slot[0]);
        Assert.Equal(8, slot[1]);
        ushort indirect = BinaryPrimitives.ReadUInt16LittleEndian(slot[28..]);
        Assert.Equal(inode.Extents[7].Start + 1, indirect);
        Assert.Equal(0, slot[30]);
        Assert.True(IsBitSet(image, indirect));

        Span<byte> spill = Block(image, indirect);
        for (int i = 0; i < 3; i++)
        {
            Extent extent = inode.Extents[5 + i];
            Assert.Equal(extent.Start, BinaryPrimitives.ReadUInt16LittleEndian(spill[(i * 3)..]));
            Assert.Equal(extent.Length, spill[(i * 3) + 2]);
        }

        Assert.False(spill[9..].ContainsAnyExcept((byte)0));
        Assert.Equal(content, Volume.Open(image).ReadFile("/fragmented"));

        volume.WriteFile("/fragmented", Pattern(300));
        Assert.False(volume.Stat("/fragmented").Inode.NeedsIndirectBlock);
        Assert.Equal(38, volume.FreeBlocks);
        AssertConsistent(volume);
    }

    [Fact]
    public void NinetyExtentsIsTheLimit()
    {
        Volume volume = Format(VolumeGeometry.Partition(2000, 512));
        for (int i = 0; i < 200; i++)
        {
            volume.WriteFile($"/f{i}", Pattern(256, i));
        }

        volume.WriteFile("/filler", Pattern((volume.FreeBlocks - 1) * 256));
        Assert.Equal(0, volume.FreeBlocks);
        for (int i = 0; i < 200; i += 2)
        {
            volume.Remove($"/f{i}");
        }

        Assert.Equal(100, volume.FreeBlocks);
        byte[] ninety = Pattern(90 * 256, 5);
        volume.WriteFile("/ninety", ninety);
        Assert.Equal(90, volume.Stat("/ninety").Inode.Extents.Length);
        Assert.Equal(ninety, Volume.Open(volume.ToImage()).ReadFile("/ninety"));
        volume.Remove("/ninety");

        C5fsException error = Assert.Throws<C5fsException>(() => volume.WriteFile("/too-many", Pattern(91 * 256)));

        Assert.Equal(C5fsError.ENOSPC, error.Error);
        Assert.Contains("91 extents", error.Message, StringComparison.Ordinal);
        Assert.Equal(100, volume.FreeBlocks);
        AssertConsistent(volume);
    }

    [Fact]
    public void FillingTheDiskFailsWithEnospcAndLeaksNothing()
    {
        Volume volume = Format180();
        volume.WriteFile("/big", Pattern(707 * 256));
        Assert.Equal("13-267,268-522,523-719", string.Join(",", volume.Stat("/big").Inode.Extents));
        Assert.Equal(0, volume.FreeBlocks);
        byte[] full = volume.ToImage();

        Assert.Equal(C5fsError.ENOSPC, ErrorOf(() => volume.WriteFile("/one", [1])));
        Assert.Equal(C5fsError.ENOSPC, ErrorOf(() => volume.CreateDirectory("/dir")));

        Assert.Equal(full, volume.ToImage());
        Assert.Empty(volume.Check());
        volume.Remove("/big");
        Assert.Equal(707, volume.FreeBlocks);
        Assert.Equal(62, volume.FreeInodes);
        AssertConsistent(volume);
    }

    [Fact]
    public void AFailedReplaceKeepsTheOldContent()
    {
        Volume volume = Format180();
        byte[] original = Pattern(400 * 256);
        volume.WriteFile("/a", original);

        Assert.Equal(C5fsError.ENOSPC, ErrorOf(() => volume.WriteFile("/a", Pattern(708 * 256))));

        Assert.Equal(original, volume.ReadFile("/a"));
        Assert.Equal(307, volume.FreeBlocks);
        byte[] whole = Pattern(707 * 256, 3);
        volume.WriteFile("/a", whole);
        Assert.Equal(whole, volume.ReadFile("/a"));
        Assert.Equal(0, volume.FreeBlocks);
        AssertConsistent(volume);
    }

    [Fact]
    public void RunningOutOfInodesFailsWithEnospc()
    {
        Volume volume = Format180();
        for (int i = 0; i < 62; i++)
        {
            volume.WriteFile($"/e{i}", []);
        }

        Assert.Equal(0, volume.FreeInodes);
        Assert.Equal(C5fsError.ENOSPC, ErrorOf(() => volume.WriteFile("/x", [])));
        Assert.Equal(C5fsError.ENOSPC, ErrorOf(() => volume.CreateDirectory("/x")));
        Assert.Equal(63 * 32, volume.Stat("/").Inode.Size);
        Assert.Equal(707 - 7, volume.FreeBlocks);
        AssertConsistent(volume);
    }

    [Fact]
    public void ReplacingKeepsTheInodeAndCreationTime()
    {
        FixedTimeProvider clock = Clock();
        Volume volume = Format(VolumeGeometry.Floppy360, clock);
        volume.WriteFile("/f", Pattern(10));
        clock.Now = clock.Now.AddHours(1);

        volume.WriteFile("/F", Pattern(3000));

        FileStatus status = volume.Stat("/f");
        Assert.Equal(2, status.InodeNumber);
        Assert.Equal(StartSeconds, status.Inode.Created.Seconds);
        Assert.Equal(StartSeconds + 3600, status.Inode.Modified.Seconds);
        Assert.Equal("f", Assert.Single(volume.List("/")).Name.Value);
        AssertConsistent(volume);
    }

    [Fact]
    public void FilesLargerThan24BitsAreRejected()
    {
        Volume volume = Format(VolumeGeometry.Partition(65535, 64));
        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => volume.WriteFile("/huge", new byte[Inode.MaxSize + 1])));
    }
}
