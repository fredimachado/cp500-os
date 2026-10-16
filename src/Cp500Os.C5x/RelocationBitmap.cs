namespace Cp500Os.C5x;

/// <summary>
/// One bit per image byte, set when the byte is the high byte of an absolute address.
/// Bit i is bit (i % 8) of byte (i / 8), least significant bit first. Bits past the image are zero.
/// </summary>
public sealed class RelocationBitmap
{
    private readonly byte[] _bytes;

    private RelocationBitmap(byte[] bytes, int length)
    {
        _bytes = bytes;
        Length = length;
    }

    /// <summary>Number of image bytes the bitmap covers.</summary>
    public int Length { get; }

    public ReadOnlySpan<byte> Bytes => _bytes;

    public static int ByteCount(int length) => (length + 7) / 8;

    /// <summary>
    /// Marks every byte that is exactly 1 higher (mod 256) in the 0100h link than in the 0000h link.
    /// Bytes that are equal stay unmarked; any other difference is an error.
    /// </summary>
    public static RelocationBitmap FromLinks(ReadOnlySpan<byte> link0000, ReadOnlySpan<byte> link0100)
    {
        if (link0000.Length != link0100.Length)
            throw new C5xException(new LinkLengthMismatch(link0000.Length, link0100.Length));

        var bytes = new byte[ByteCount(link0000.Length)];
        var differences = new List<LinkDifference>();
        for (int i = 0; i < link0000.Length; i++)
        {
            switch ((byte)(link0100[i] - link0000[i]))
            {
                case 0:
                    break;
                case 1:
                    bytes[i / 8] |= (byte)(1 << (i % 8));
                    break;
                default:
                    differences.Add(new LinkDifference(i, link0000[i], link0100[i]));
                    break;
            }
        }

        if (differences.Count > 0)
            throw new C5xException(new NonRelocatableDifferences(differences));

        return new RelocationBitmap(bytes, link0000.Length);
    }

    /// <summary>Reads the stored form of a bitmap covering <paramref name="length"/> image bytes.</summary>
    public static RelocationBitmap FromBytes(ReadOnlySpan<byte> bytes, int length)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(length);
        if (bytes.Length != ByteCount(length))
            throw new ArgumentException($"A bitmap for {length} bytes is {ByteCount(length)} bytes long, not {bytes.Length}.", nameof(bytes));

        int usedBitsInLastByte = length % 8;
        if (usedBitsInLastByte != 0 && (bytes[^1] >> usedBitsInLastByte) != 0)
            throw new C5xException(new BitmapPaddingNotZero());

        return new RelocationBitmap(bytes.ToArray(), length);
    }

    public bool IsMarked(int offset)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(offset);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(offset, Length);
        return (_bytes[offset / 8] & (1 << (offset % 8))) != 0;
    }

    public IEnumerable<int> MarkedOffsets() => Enumerable.Range(0, Length).Where(IsMarked);
}
