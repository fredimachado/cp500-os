namespace Cp500Os.C5x.Tests;

public class RelocationBitmapTests
{
    [Fact]
    public void MarksTheHighBytesOfAbsoluteAddressesLeastSignificantBitFirst()
    {
        var bitmap = RelocationBitmap.FromLinks(SampleProgram.At0000, SampleProgram.At0100);

        Assert.Equal(SampleProgram.Bitmap, bitmap.Bytes.ToArray());
        Assert.Equal(SampleProgram.RelocatedOffsets, bitmap.MarkedOffsets());
        Assert.Equal(12, bitmap.Length);
    }

    [Fact]
    public void ADifferenceOfOneWrapsModulo256()
    {
        var bitmap = RelocationBitmap.FromLinks([0x12, 0xFF], [0x12, 0x00]);

        Assert.Equal([0x02], bitmap.Bytes.ToArray());
    }

    [Fact]
    public void EightBytesFillExactlyOneBitmapByte()
    {
        var bitmap = RelocationBitmap.FromLinks(new byte[8], [1, 0, 0, 0, 0, 0, 0, 1]);

        Assert.Equal([0x81], bitmap.Bytes.ToArray());
    }

    [Fact]
    public void AnEmptyLinkHasAnEmptyBitmap()
    {
        var bitmap = RelocationBitmap.FromLinks([], []);

        Assert.Empty(bitmap.Bytes.ToArray());
    }

    [Fact]
    public void RejectsLinksOfDifferentLengths()
    {
        var exception = Assert.Throws<C5xException>(() => RelocationBitmap.FromLinks(new byte[12], new byte[13]));

        Assert.Equal(new LinkLengthMismatch(12, 13), exception.Error);
        Assert.Equal("The two links differ in length: 12 bytes at 0000h, 13 bytes at 0100h.", exception.Message);
    }

    [Fact]
    public void RejectsBytesThatDifferByAnythingButOne()
    {
        byte[] at0000 = [0x00, 0x00, 0x10, 0x05];
        byte[] at0100 = [0x01, 0x02, 0x10, 0x04];

        var exception = Assert.Throws<C5xException>(() => RelocationBitmap.FromLinks(at0000, at0100));

        Assert.Equal(new NonRelocatableDifferences([new(1, 0x00, 0x02), new(3, 0x05, 0x04)]), exception.Error);
        Assert.Equal(
            "2 byte(s) differ between the links by something other than +1: 0001h (00h -> 02h), 0003h (05h -> 04h).",
            exception.Message);
    }

    [Fact]
    public void ReportsTheFirstEightDifferencesAndCountsTheRest()
    {
        var at0100 = Enumerable.Repeat((byte)0x80, 10).ToArray();

        var exception = Assert.Throws<C5xException>(() => RelocationBitmap.FromLinks(new byte[10], at0100));

        Assert.Equal(10, ((NonRelocatableDifferences)exception.Error).Differences.Count);
        Assert.EndsWith("0007h (00h -> 80h), and 2 more.", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void StoredBytesRoundTrip()
    {
        var bitmap = RelocationBitmap.FromBytes(SampleProgram.Bitmap, 12);

        Assert.Equal(SampleProgram.RelocatedOffsets, bitmap.MarkedOffsets());
    }

    [Fact]
    public void StoredBytesMustHaveZeroPaddingBits()
    {
        var exception = Assert.Throws<C5xException>(() => RelocationBitmap.FromBytes([0x04, 0x19], 12));

        Assert.IsType<BitmapPaddingNotZero>(exception.Error);
    }
}
