namespace Cp500Os.C5x.Tests;

public class C5xFileTests
{
    private static readonly byte[] SampleFile =
    [
        0x43, 0x35, 0x58, 0x01, // "C5X", version 1
        0x0C, 0x00,             // image size 12
        0x10, 0x00,             // bss 16
        0x00, 0x01,             // stack 256
        0x06, 0x00,             // entry 0006h
        0x00, 0x00, 0x00, 0x00, // reserved
        .. SampleProgram.At0000,
        .. SampleProgram.Bitmap,
    ];

    private static C5xProgram Sample() => C5xProgram.FromLinks(SampleProgram.At0000, SampleProgram.At0100, 16, 256, 6);

    [Fact]
    public void WritesHeaderImageAndBitmap()
    {
        Assert.Equal(SampleFile, C5xFile.Write(Sample()));
    }

    [Fact]
    public void ParsesWhatItWrites()
    {
        var program = C5xFile.Parse(SampleFile);

        Assert.Equal(new C5xHeader(12, 16, 256, 6), program.Header);
        Assert.Equal(SampleProgram.At0000, program.Image.ToArray());
        Assert.Equal(SampleProgram.RelocatedOffsets, program.Relocations.MarkedOffsets());
        Assert.Equal(SampleProgram.At6200, program.RelocateTo(0x62));
    }

    [Fact]
    public void RejectsAFileShorterThanTheHeader()
    {
        AssertRejected(SampleFile[..15], new Truncated(16, 15));
    }

    [Fact]
    public void RejectsBadMagic()
    {
        AssertRejected(With(SampleFile, 2, (byte)'Y'), new BadMagic(0x43, 0x35, 0x59));
    }

    [Fact]
    public void RejectsOtherVersions()
    {
        AssertRejected(With(SampleFile, 3, 2), new UnsupportedVersion(2));
    }

    [Theory]
    [InlineData(12)]
    [InlineData(15)]
    public void RejectsNonZeroReservedBytes(int offset)
    {
        AssertRejected(With(SampleFile, offset, 1), new ReservedNotZero());
    }

    [Fact]
    public void RejectsATruncatedImageOrBitmap()
    {
        AssertRejected(SampleFile[..^1], new Truncated(30, 29));
    }

    [Fact]
    public void RejectsBytesAfterTheBitmap()
    {
        AssertRejected([.. SampleFile, 0x00], new TrailingData(30, 31));
    }

    [Fact]
    public void RejectsAnEntryOutsideTheImage()
    {
        AssertRejected(With(SampleFile, 10, 12), new EntryOutsideImage(12, 12));
    }

    [Fact]
    public void RejectsSetBitmapPaddingBits()
    {
        AssertRejected(With(SampleFile, 29, 0x19), new BitmapPaddingNotZero());
    }

    [Fact]
    public void RejectsSizesThatDoNotFitTheArena()
    {
        // bss FFFFh
        AssertRejected(With(With(SampleFile, 6, 0xFF), 7, 0xFF), new ProgramTooLarge(12, 0xFFFF, 256));
    }

    private static byte[] With(byte[] bytes, int offset, byte value)
    {
        var copy = bytes.ToArray();
        copy[offset] = value;
        return copy;
    }

    private static void AssertRejected(byte[] file, C5xError expected)
    {
        var exception = Assert.Throws<C5xException>(() => C5xFile.Parse(file));
        Assert.Equal(expected, exception.Error);
    }
}
