using Cp500Os.C5fs;
using static Cp500Os.C5fs.Tests.TestSupport;

namespace Cp500Os.C5fs.Tests;

public sealed class HardDiskTests
{
    [Fact]
    public void BuildReadOpenAndCheck()
    {
        Volume small = Format(VolumeGeometry.Partition(2000, 128));
        Volume big = Format(VolumeGeometry.Partition(16000, 512));
        small.WriteFile("/notes", Pattern(400, 2));
        big.WriteFile("/log", Pattern(800, 4));

        byte[] disk = HardDisk.Build([small, big]);
        PartitionTable table = HardDisk.ReadTable(disk);
        Assert.Equal(2, table.Entries.Count);
        Assert.Equal(new PartitionEntry(1, 1, 2000), table.Find(1));
        Assert.Equal(new PartitionEntry(2, 2001, 16000), table.Find(2));

        Volume again = HardDisk.OpenPartition(disk, 1);
        Assert.Equal(Pattern(400, 2), again.ReadFile("/notes"));
        AssertConsistent(again);

        Volume slot2 = HardDisk.OpenPartition(disk, 2);
        Assert.Equal(Pattern(800, 4), slot2.ReadFile("/log"));
        AssertConsistent(slot2);
    }

    [Fact]
    public void WritePartitionTouchesOnlyItsRange()
    {
        Volume one = Format(VolumeGeometry.Partition(100, 64));
        Volume two = Format(VolumeGeometry.Partition(100, 64));
        byte[] disk = HardDisk.Build([one, two]);
        byte[] before = disk.ToArray();

        two.WriteFile("/x", [1, 2, 3]);
        HardDisk.WritePartition(disk, 2, two);

        Assert.Equal(before.AsSpan(0, 256 * 101), disk.AsSpan(0, 256 * 101));
        Assert.False(before.AsSpan(256 * 101, 256 * 100).SequenceEqual(disk.AsSpan(256 * 101, 256 * 100)));
    }

    [Fact]
    public void EmptySlotIsEnoent()
    {
        byte[] disk = HardDisk.Build([Format(VolumeGeometry.Partition(50, 64)), null, null, null]);
        Assert.Equal(C5fsError.ENOENT, ErrorOf(() => HardDisk.OpenPartition(disk, 3)));
    }

    [Fact]
    public void WrongSizeIsEinval()
    {
        byte[] disk = HardDisk.Build([Format(VolumeGeometry.Partition(50, 64))]);
        Volume resized = Format(VolumeGeometry.Partition(60, 64));
        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => HardDisk.WritePartition(disk, 1, resized)));
    }

    [Fact]
    public void FloppyGeometryIsEinval()
    {
        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => HardDisk.Build([Format360()])));
    }
}
