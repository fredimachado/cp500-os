using Cp500Os.C5fs;
using static Cp500Os.C5fs.Tests.TestSupport;

namespace Cp500Os.C5fs.Tests;

public sealed class PartitionTableTests
{
    [Fact]
    public void KnownLayoutMatchesKernelEquates()
    {
        byte[] block = new PartitionTable(
        [
            new PartitionEntry(1, 1, 2000),
            new PartitionEntry(2, 2001, 16000),
        ]).ToBlock();

        Assert.Equal(
            new byte[]
            {
                0x01, 0x01, 0x00, 0x00, 0xD0, 0x07, 0x00,
                0x01, 0xD1, 0x07, 0x00, 0x80, 0x3E, 0x00,
            },
            block.AsSpan(0, 14).ToArray());
        for (int i = 14; i < block.Length; i++)
        {
            Assert.Equal(0, block[i]);
        }
    }

    [Fact]
    public void RoundTripThroughParse()
    {
        PartitionTable table = new(
        [
            new PartitionEntry(1, 1, 2000),
            new PartitionEntry(2, 2001, 16000),
        ]);
        Assert.Equal(table.Entries, PartitionTable.Parse(table.ToBlock()).Entries);
    }

    [Theory]
    [InlineData(2)]
    [InlineData(0x10)]
    public void ParseRejectsBadType(byte type)
    {
        byte[] block = new PartitionTable([new PartitionEntry(1, 1, 2000)]).ToBlock();
        block[0] = type;
        Assert.Equal(C5fsError.EIO, ErrorOf(() => PartitionTable.Parse(block)));
    }

    [Fact]
    public void ParseRejectsNonZeroEmptySlot()
    {
        byte[] block = new byte[256];
        block[7] = 1;
        Assert.Equal(C5fsError.EIO, ErrorOf(() => PartitionTable.Parse(block)));
    }

    [Fact]
    public void ParseRejectsTailBytes()
    {
        byte[] block = new PartitionTable([new PartitionEntry(1, 1, 2000)]).ToBlock();
        block[28] = 1;
        Assert.Equal(C5fsError.EIO, ErrorOf(() => PartitionTable.Parse(block)));
    }

    [Fact]
    public void ParseRejectsStartZero()
    {
        byte[] block = new byte[256];
        block[0] = PartitionTable.C5fsType;
        Assert.Equal(C5fsError.EIO, ErrorOf(() => PartitionTable.Parse(block)));
    }

    [Fact]
    public void ParseRejectsOverlap()
    {
        byte[] block = new byte[256];
        block[0] = PartitionTable.C5fsType;
        block[1] = 1;
        block[4] = 0x10;
        block[0 + 7] = PartitionTable.C5fsType;
        block[0 + 7 + 1] = 8;
        block[0 + 7 + 4] = 0x10;
        Assert.Equal(C5fsError.EIO, ErrorOf(() => PartitionTable.Parse(block)));
    }

    [Fact]
    public void ConstructorRejectsZeroCount()
    {
        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => _ = new PartitionTable([new PartitionEntry(1, 1, 0)])));
    }

    [Fact]
    public void ConstructorRejectsCount65536()
    {
        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => _ = new PartitionTable([new PartitionEntry(1, 1, 65536)])));
    }

    [Fact]
    public void ConstructorRejectsEndPastLimit()
    {
        Assert.Equal(
            C5fsError.EINVAL,
            ErrorOf(() => _ = new PartitionTable([new PartitionEntry(1, PartitionTable.BlockLimit, 1)])));
    }
}
