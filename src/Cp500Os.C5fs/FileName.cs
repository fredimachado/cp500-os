namespace Cp500Os.C5fs;

/// <summary>
/// A valid C5FS name: 1-30 printable ISO-8859-1 bytes, no '/', not "." or "..".
/// Case is preserved; equality and ordering fold case, including accented letters.
/// </summary>
public sealed class FileName : IEquatable<FileName>, IComparable<FileName>
{
    public const int MaxLength = 30;

    private readonly byte[] _bytes;
    private readonly byte[] _folded;

    private FileName(byte[] bytes)
    {
        _bytes = bytes;
        _folded = Array.ConvertAll(bytes, Latin1Text.Fold);
    }

    public string Value => Latin1Text.Decode(_bytes);

    public ReadOnlySpan<byte> Bytes => _bytes;

    public static FileName Parse(string name)
    {
        ArgumentNullException.ThrowIfNull(name);
        byte[] bytes = Latin1Text.Encode(name, "name");
        string? problem = Validate(bytes);
        return problem is null
            ? new FileName(bytes)
            : throw new C5fsException(C5fsError.EINVAL, $"invalid name '{name}': {problem}");
    }

    /// <summary>Decodes a 30-byte NUL-padded directory entry name field; null when it is not a valid name.</summary>
    internal static FileName? TryDecode(ReadOnlySpan<byte> field)
    {
        int length = field.IndexOf((byte)0);
        if (length < 0)
        {
            length = field.Length;
        }
        else if (field[length..].ContainsAnyExcept((byte)0))
        {
            return null;
        }

        byte[] bytes = field[..length].ToArray();
        return Validate(bytes) is null ? new FileName(bytes) : null;
    }

    internal void EncodeTo(Span<byte> field)
    {
        field.Clear();
        _bytes.CopyTo(field);
    }

    public bool Equals(FileName? other) => other is not null && _folded.AsSpan().SequenceEqual(other._folded);

    public override bool Equals(object? obj) => Equals(obj as FileName);

    public override int GetHashCode()
    {
        HashCode hash = default;
        hash.AddBytes(_folded);
        return hash.ToHashCode();
    }

    public int CompareTo(FileName? other) =>
        other is null ? 1 : _folded.AsSpan().SequenceCompareTo(other._folded);

    public override string ToString() => Value;

    public static bool operator ==(FileName? left, FileName? right) => left?.Equals(right) ?? right is null;

    public static bool operator !=(FileName? left, FileName? right) => !(left == right);

    public static bool operator <(FileName? left, FileName? right) => Compare(left, right) < 0;

    public static bool operator <=(FileName? left, FileName? right) => Compare(left, right) <= 0;

    public static bool operator >(FileName? left, FileName? right) => Compare(left, right) > 0;

    public static bool operator >=(FileName? left, FileName? right) => Compare(left, right) >= 0;

    private static int Compare(FileName? left, FileName? right) =>
        left is null ? (right is null ? 0 : -1) : left.CompareTo(right);

    private static string? Validate(byte[] bytes)
    {
        if (bytes.Length == 0)
        {
            return "a name cannot be empty";
        }

        if (bytes.Length > MaxLength)
        {
            return $"{bytes.Length} bytes, the limit is {MaxLength}";
        }

        if (bytes.AsSpan().SequenceEqual("."u8) || bytes.AsSpan().SequenceEqual(".."u8))
        {
            return "'.' and '..' are reserved";
        }

        foreach (byte value in bytes)
        {
            if (value == (byte)'/')
            {
                return "'/' is not allowed in a name";
            }

            if (!Latin1Text.IsPrintable(value))
            {
                return $"byte 0x{value:X2} is not a printable character";
            }
        }

        return null;
    }
}
