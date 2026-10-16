namespace Cp500Os.C5fs;

/// <summary>A run of 1-255 consecutive blocks.</summary>
public readonly record struct Extent
{
    public const int MaxLength = 255;

    public Extent(int start, int length)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(start, 0);
        ArgumentOutOfRangeException.ThrowIfLessThan(length, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(length, MaxLength);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(start + length, ushort.MaxValue + 1, nameof(length));
        Start = (ushort)start;
        Length = (byte)length;
    }

    public ushort Start { get; }

    public byte Length { get; }

    /// <summary>The block just past the extent.</summary>
    public int End => Start + Length;

    public IEnumerable<int> Blocks => Enumerable.Range(Start, Length);

    public override string ToString() => Length == 1 ? $"{Start}" : $"{Start}-{End - 1}";
}
