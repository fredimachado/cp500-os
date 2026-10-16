namespace Cp500Os.C5x.Tests;

public class C5xHeaderTests
{
    [Fact]
    public void CountsTheKernelStackReserveInTheAllocation()
    {
        var header = new C5xHeader(imageSize: 1000, bssSize: 100, stackSize: 256, entryOffset: 0);

        Assert.Equal(1548, header.MemoryBytes);
        Assert.Equal(7, header.MemoryPages);
    }

    [Fact]
    public void AcceptsAProgramThatFillsTheArenaExactly()
    {
        var header = new C5xHeader(imageSize: 12, bssSize: 40_244, stackSize: 0, entryOffset: 0);

        Assert.Equal(40_448, header.MemoryBytes);
        Assert.Equal(158, header.MemoryPages);
    }

    [Fact]
    public void RejectsAProgramOneByteLargerThanTheArena()
    {
        var exception = Assert.Throws<C5xException>(() => new C5xHeader(12, 40_245, 0, 0));

        Assert.Equal(new ProgramTooLarge(12, 40_245, 0), exception.Error);
        Assert.Equal(
            "Image 12 + bss 40245 + stack 0 + kernel reserve 192 = 40449 bytes, more than the 40448-byte arena.",
            exception.Message);
    }

    [Fact]
    public void RejectsAnEntryPastTheLastImageByte()
    {
        var exception = Assert.Throws<C5xException>(() => new C5xHeader(12, 0, 256, 12));

        Assert.Equal(new EntryOutsideImage(12, 12), exception.Error);
        Assert.Equal("Entry offset 000Ch is outside the 12-byte image.", exception.Message);
    }

    [Fact]
    public void RejectsAnEmptyImage()
    {
        var exception = Assert.Throws<C5xException>(() => new C5xHeader(0, 0, 256, 0));

        Assert.Equal(new EntryOutsideImage(0, 0), exception.Error);
    }

    [Fact]
    public void ProgramFromLinksRejectsALinkLargerThanTheArena()
    {
        var link = new byte[40_257];

        var exception = Assert.Throws<C5xException>(() => C5xProgram.FromLinks(link, link, 0, 0, 0));

        Assert.Equal(new ProgramTooLarge(40_257, 0, 0), exception.Error);
    }
}
