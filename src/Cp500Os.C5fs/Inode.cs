using System.Collections.Immutable;

namespace Cp500Os.C5fs;

public enum InodeKind : byte
{
    File = 1,
    Directory = 2,
}

[Flags]
public enum InodeAttributes : byte
{
    None = 0,
    ReadOnly = 0x10,
    Hidden = 0x20,
}

/// <summary>
/// An allocated inode. Free slots are not represented by an instance.
/// A file owns exactly ceil(size / 256) data blocks; nothing is preallocated.
/// </summary>
public sealed class Inode
{
    public const int RecordSize = 32;
    public const int InlineExtents = 6;
    public const int MaxExtents = 90;
    public const int MaxSize = 0xFFFFFF;
    public const int DirectoryEntrySize = 32;

    public Inode(
        InodeKind kind,
        InodeAttributes attributes,
        int size,
        C5Time modified,
        C5Time created,
        ImmutableArray<Extent> extents)
    {
        if (!Enum.IsDefined(kind))
        {
            throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unknown inode kind.");
        }

        if ((attributes & ~(InodeAttributes.ReadOnly | InodeAttributes.Hidden)) != 0)
        {
            throw new ArgumentOutOfRangeException(nameof(attributes), attributes, "Unknown inode attributes.");
        }

        ArgumentOutOfRangeException.ThrowIfNegative(size);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(size, MaxSize);
        if (kind == InodeKind.Directory && (size < DirectoryEntrySize || size % DirectoryEntrySize != 0))
        {
            throw new ArgumentOutOfRangeException(nameof(size), size, "A directory size is a non-zero multiple of 32.");
        }

        ArgumentOutOfRangeException.ThrowIfGreaterThan(extents.Length, MaxExtents, nameof(extents));
        int blocks = extents.Sum(extent => extent.Length);
        if (blocks != BlocksFor(size))
        {
            throw new ArgumentException($"{size} bytes need {BlocksFor(size)} blocks, the extents hold {blocks}.", nameof(extents));
        }

        Kind = kind;
        Attributes = attributes;
        Size = size;
        Modified = modified;
        Created = created;
        Extents = extents;
    }

    public InodeKind Kind { get; }

    public InodeAttributes Attributes { get; }

    /// <summary>Size in bytes (24-bit).</summary>
    public int Size { get; }

    public C5Time Modified { get; }

    public C5Time Created { get; }

    public ImmutableArray<Extent> Extents { get; }

    public bool IsDirectory => Kind == InodeKind.Directory;

    public int BlockCount => BlocksFor(Size);

    /// <summary>More than 6 extents spill into an indirect block.</summary>
    public bool NeedsIndirectBlock => Extents.Length > InlineExtents;

    public static int BlocksFor(int size) => (size + VolumeGeometry.BlockSize - 1) / VolumeGeometry.BlockSize;

    internal Inode WithContent(int size, ImmutableArray<Extent> extents, C5Time modified) =>
        new(Kind, Attributes, size, modified, Created, extents);

    internal Inode WithModified(C5Time modified) => new(Kind, Attributes, Size, modified, Created, Extents);
}
