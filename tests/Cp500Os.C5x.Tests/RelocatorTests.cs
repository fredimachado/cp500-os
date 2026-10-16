namespace Cp500Os.C5x.Tests;

public class RelocatorTests
{
    private static readonly RelocationBitmap SampleBitmap =
        RelocationBitmap.FromLinks(SampleProgram.At0000, SampleProgram.At0100);

    [Fact]
    public void PageOneReproducesTheLinkAt0100h()
    {
        Assert.Equal(SampleProgram.At0100, Relocator.Relocate(SampleProgram.At0000, SampleBitmap, 0x01));
    }

    [Fact]
    public void Page62hReproducesTheLinkAt6200h()
    {
        Assert.Equal(SampleProgram.At6200, Relocator.Relocate(SampleProgram.At0000, SampleBitmap, 0x62));
    }

    [Fact]
    public void PageZeroLeavesTheImageUnchanged()
    {
        Assert.Equal(SampleProgram.At0000, Relocator.Relocate(SampleProgram.At0000, SampleBitmap, 0x00));
    }

    [Fact]
    public void AdditionWrapsModulo256()
    {
        var bitmap = RelocationBitmap.FromLinks([0xFF], [0x00]);

        Assert.Equal([0x01], Relocator.Relocate([0xFF], bitmap, 0x02));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(4)]
    [InlineData(5)]
    public void RelocatingALinkAt0000hToAnyPageEqualsLinkingAtThatPage(int seed)
    {
        var program = SyntheticProgram.Generate(new Random(seed));
        var bitmap = RelocationBitmap.FromLinks(program.LinkAt(0x00), program.LinkAt(0x01));

        foreach (byte page in new byte[] { 0x01, 0x62, 0x9F })
            Assert.Equal(program.LinkAt(page), Relocator.Relocate(program.LinkAt(0x00), bitmap, page));
    }

    [Fact]
    public void RejectsABitmapForAnotherLength()
    {
        Assert.Throws<ArgumentException>(() => Relocator.Relocate(new byte[13], SampleBitmap, 0x62));
    }

    /// <summary>Opaque bytes mixed with little-endian absolute addresses inside the program, linkable at any page.</summary>
    private sealed class SyntheticProgram
    {
        private readonly List<(bool IsAddress, int Value)> _items = [];

        public static SyntheticProgram Generate(Random random)
        {
            var program = new SyntheticProgram();
            int length = 0;
            while (length < 600)
            {
                bool isAddress = random.Next(3) == 0;
                program._items.Add((isAddress, isAddress ? 0 : random.Next(256)));
                length += isAddress ? 2 : 1;
            }

            for (int i = 0; i < program._items.Count; i++)
            {
                if (program._items[i].IsAddress)
                    program._items[i] = (true, random.Next(length));
            }

            return program;
        }

        public byte[] LinkAt(byte page)
        {
            var bytes = new List<byte>();
            foreach (var (isAddress, value) in _items)
            {
                if (!isAddress)
                {
                    bytes.Add((byte)value);
                    continue;
                }

                int address = (page << 8) + value;
                bytes.Add((byte)address);
                bytes.Add((byte)(address >> 8));
            }

            return [.. bytes];
        }
    }
}
