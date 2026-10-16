namespace Cp500Os.C5fs;

/// <summary>
/// Allocation bitmap: block n is bit n % 8 of byte n / 8, 1 = used. Metadata blocks and the
/// padding bits past the last block are always 1, so a byte-wise scan never hands them out.
/// </summary>
internal sealed class Bitmap(BlockStore store, VolumeGeometry geometry)
{
    public int PaddedBitCount => geometry.BitmapLength * VolumeGeometry.BitsPerBitmapBlock;

    public void Initialize()
    {
        for (int i = 0; i < geometry.BitmapLength; i++)
        {
            store.Write(VolumeGeometry.BitmapStart + i).Clear();
        }

        for (int block = 0; block < geometry.FirstDataBlock; block++)
        {
            SetBit(block, true);
        }

        for (int bit = geometry.BlockCount; bit < PaddedBitCount; bit++)
        {
            SetBit(bit, true);
        }
    }

    public bool IsUsed(int block)
    {
        (int bitmapBlock, int index, byte mask) = Locate(block);
        return (store.Read(bitmapBlock)[index] & mask) != 0;
    }

    public void Allocate(Extent extent) => SetRange(extent, true);

    public void Free(Extent extent) => SetRange(extent, false);

    public int CountFree()
    {
        int free = 0;
        for (int block = geometry.FirstDataBlock; block < geometry.BlockCount; block++)
        {
            free += IsUsed(block) ? 0 : 1;
        }

        return free;
    }

    /// <summary>Number of free blocks starting at <paramref name="start"/>, up to <paramref name="max"/>.</summary>
    public int FreeRunLength(int start, int max)
    {
        int length = 0;
        while (length < max && start + length < geometry.BlockCount && !IsUsed(start + length))
        {
            length++;
        }

        return length;
    }

    /// <summary>Start of the lowest-numbered run of at least <paramref name="length"/> free blocks.</summary>
    public int? FirstFit(int length)
    {
        int block = geometry.FirstDataBlock;
        while (block < geometry.BlockCount)
        {
            int run = FreeRunLength(block, length);
            if (run == length)
            {
                return block;
            }

            block += run + 1;
        }

        return null;
    }

    public int? FirstFree()
    {
        for (int block = geometry.FirstDataBlock; block < geometry.BlockCount; block++)
        {
            if (!IsUsed(block))
            {
                return block;
            }
        }

        return null;
    }

    private void SetRange(Extent extent, bool used)
    {
        foreach (int block in extent.Blocks)
        {
            if (block < geometry.FirstDataBlock || block >= geometry.BlockCount)
            {
                throw new InvalidOperationException($"Block {block} is outside the data area.");
            }

            SetBit(block, used);
        }
    }

    private void SetBit(int bit, bool used)
    {
        (int bitmapBlock, int index, byte mask) = Locate(bit);
        Span<byte> bytes = store.Write(bitmapBlock);
        bytes[index] = used ? (byte)(bytes[index] | mask) : (byte)(bytes[index] & ~mask);
    }

    private static (int BitmapBlock, int Index, byte Mask) Locate(int bit) =>
        (VolumeGeometry.BitmapStart + (bit / VolumeGeometry.BitsPerBitmapBlock),
         bit % VolumeGeometry.BitsPerBitmapBlock / 8,
         (byte)(1 << (bit % 8)));
}
