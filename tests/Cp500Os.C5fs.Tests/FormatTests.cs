using System.Buffers.Binary;
using static Cp500Os.C5fs.Tests.TestSupport;

namespace Cp500Os.C5fs.Tests;

public class FormatTests
{
    [Fact]
    public void Format360HasTheDocumentedLayout()
    {
        byte[] image = Format360().ToImage();

        Assert.Equal(368_640, image.Length);
        Superblock superblock = Volume.Open(image).Superblock;
        Assert.Equal(1440, superblock.Geometry.BlockCount);
        Assert.Equal(1, superblock.Geometry.BitmapLength);
        Assert.Equal(4, superblock.Geometry.InodeTableStart);
        Assert.Equal(16, superblock.Geometry.InodeTableLength);
        Assert.Equal(128, superblock.Geometry.InodeCount);
        Assert.Equal(20, superblock.Geometry.FirstDataBlock);
        Assert.Equal(2, superblock.Geometry.Sides);

        Span<byte> a = Block(image, 1);
        Assert.Equal("C5FS"u8.ToArray(), a[..4].ToArray());
        Assert.Equal(
            [
                0x01, // version
                0x01, // clean
                0x01, 0x00, 0x00, 0x00, // sequence 1 in copy A
                0x78, 0x56, 0x34, 0x12, // volume id
                0x01, 0x00, // generation
                0xA0, 0x05, // 1440 blocks
                0x03, 0x00, // bitmap start
                0x01, // bitmap length
                0x04, 0x00, // inode table start
                0x80, 0x00, // 128 inodes
                0x14, 0x00, // first data block 20
                0x02, 0x28, 0x12, // 2 sides, 40 tracks, 18 sectors
                0x00, 0x00, 0x00, 0x00, // no kernel
                0xA0, 0x4F, 0x03, 0x58, // created 1476612000
                0xA0, 0x4F, 0x03, 0x58, // last written
                (byte)'T', (byte)'E', (byte)'S', (byte)'T', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            ],
            a[4..58].ToArray());
        Assert.False(a[58..254].ContainsAnyExcept((byte)0));
        Assert.Equal(Crc16Ccitt.Compute(a[..254]), BinaryPrimitives.ReadUInt16LittleEndian(a[254..]));
        Assert.Equal(1u, SequenceIn(image, SuperblockCopy.A));
        Assert.Equal(2u, SequenceIn(image, SuperblockCopy.B));
        Assert.Equal(a[10..254].ToArray(), Block(image, 2)[10..254].ToArray());
    }

    [Fact]
    public void Format360BitmapMarksMetadataRootAndPadding()
    {
        byte[] image = Format360().ToImage();
        Span<byte> bitmap = Block(image, 3);

        Assert.Equal([0xFF, 0xFF, 0x1F, 0x00], bitmap[..4].ToArray());
        Assert.False(bitmap[3..180].ContainsAnyExcept((byte)0));
        Assert.False(bitmap[180..].ContainsAnyExcept((byte)0xFF));
    }

    [Fact]
    public void Format180HasTheDocumentedLayout()
    {
        Volume volume = Format180();
        byte[] image = volume.ToImage();

        Assert.Equal(184_320, image.Length);
        Assert.Equal(720, volume.Geometry.BlockCount);
        Assert.Equal(64, volume.Geometry.InodeCount);
        Assert.Equal(4, volume.Geometry.InodeTableStart);
        Assert.Equal(12, volume.Geometry.FirstDataBlock);
        Assert.Equal((1, 40, 18), (volume.Geometry.Sides, volume.Geometry.Tracks, volume.Geometry.SectorsPerTrack));
        Assert.Equal([0xD0, 0x02], Block(image, 1)[16..18].ToArray());

        Span<byte> bitmap = Block(image, 3);
        Assert.Equal([0xFF, 0x1F, 0x00], bitmap[..3].ToArray());
        Assert.False(bitmap[2..90].ContainsAnyExcept((byte)0));
        Assert.False(bitmap[90..].ContainsAnyExcept((byte)0xFF));
        Assert.Equal(707, volume.FreeBlocks);
        Assert.Equal(62, volume.FreeInodes);
    }

    [Fact]
    public void RootDirectoryIsInode1WithOnlyDotDotPointingAtItself()
    {
        Volume volume = Format360();
        byte[] image = volume.ToImage();

        Assert.False(Block(image, 4)[..32].ContainsAnyExcept((byte)0));
        Assert.Equal(
            [0x02, 0x01, 0x20, 0x00, 0x00, 0xA0, 0x4F, 0x03, 0x58, 0xA0, 0x4F, 0x03, 0x58, 0x14, 0x00, 0x01],
            Block(image, 4)[32..48].ToArray());
        Assert.False(Block(image, 4)[48..].ContainsAnyExcept((byte)0));
        Assert.Equal([0x01, 0x00, (byte)'.', (byte)'.', 0x00], Block(image, 20)[..5].ToArray());
        Assert.False(Block(image, 20)[5..].ContainsAnyExcept((byte)0));
        Assert.Empty(volume.List("/"));
        Assert.Equal(1419, volume.FreeBlocks);
        Assert.Equal(126, volume.FreeInodes);
        AssertConsistent(volume);
    }

    [Fact]
    public void RandomVolumeIdsDiffer()
    {
        uint first = Volume.Format(new FormatOptions()).Superblock.VolumeId;
        uint second = Volume.Format(new FormatOptions()).Superblock.VolumeId;
        Assert.NotEqual(first, second);
    }

    [Fact]
    public void LabelsAreLimitedTo16Bytes()
    {
        Assert.Equal("SIXTEEN-CHARS-OK", Format(VolumeGeometry.Floppy180, label: "SIXTEEN-CHARS-OK").Superblock.Label);
        Assert.Equal(
            C5fsError.EINVAL,
            ErrorOf(() => Format(VolumeGeometry.Floppy180, label: "SEVENTEEN-CHARS-X")));
    }

    [Fact]
    public void PartitionGeometryScalesTheBitmap()
    {
        Volume volume = Format(VolumeGeometry.Partition(65535, 1024));

        Assert.Equal(32, volume.Geometry.BitmapLength);
        Assert.Equal(35, volume.Geometry.InodeTableStart);
        Assert.Equal(163, volume.Geometry.FirstDataBlock);
        Assert.Equal(65535 - 164, volume.FreeBlocks);
        volume.WriteFile("/big", Pattern(300_000));
        Assert.Equal(Pattern(300_000), volume.ReadFile("/big"));
        AssertConsistent(volume);
    }

    [Fact]
    public void InvalidGeometriesAreRejected()
    {
        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => VolumeGeometry.Partition(1000, 12)));
        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => VolumeGeometry.Partition(20, 128)));
    }
}
