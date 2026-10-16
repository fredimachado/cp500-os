using System.Collections.Immutable;

namespace Cp500Os.C5fs;

/// <summary>An absolute, '/'-separated path inside a volume, at most 127 bytes (the kernel's path limit).</summary>
public sealed class VolumePath : IEquatable<VolumePath>
{
    public const int MaxLength = 127;

    private VolumePath(ImmutableArray<FileName> segments)
    {
        Segments = segments;
    }

    public static VolumePath Root { get; } = new([]);

    public ImmutableArray<FileName> Segments { get; }

    public bool IsRoot => Segments.IsEmpty;

    public FileName Name => IsRoot
        ? throw new InvalidOperationException("The root directory has no name.")
        : Segments[^1];

    public VolumePath Parent => IsRoot ? this : new VolumePath(Segments[..^1]);

    /// <summary>Parses an absolute path. Repeated and trailing slashes are ignored.</summary>
    public static VolumePath Parse(string path)
    {
        ArgumentNullException.ThrowIfNull(path);
        if (!path.StartsWith('/'))
        {
            throw new C5fsException(C5fsError.EINVAL, $"path '{path}' must be absolute (start with '/')");
        }

        VolumePath parsed = new([.. path.Split('/', StringSplitOptions.RemoveEmptyEntries).Select(FileName.Parse)]);
        int length = parsed.IsRoot ? 1 : parsed.Segments.Sum(segment => segment.Bytes.Length + 1);
        return length <= MaxLength
            ? parsed
            : throw new C5fsException(C5fsError.EINVAL, $"path '{path}' is {length} bytes, the limit is {MaxLength}");
    }

    public VolumePath Append(FileName name) => new(Segments.Add(name));

    public bool Equals(VolumePath? other) => other is not null && Segments.SequenceEqual(other.Segments);

    public override bool Equals(object? obj) => Equals(obj as VolumePath);

    public override int GetHashCode()
    {
        HashCode hash = default;
        foreach (FileName segment in Segments)
        {
            hash.Add(segment);
        }

        return hash.ToHashCode();
    }

    public override string ToString() => IsRoot ? "/" : "/" + string.Join('/', Segments);
}
