using System.Collections.Immutable;

namespace Cp500Os.C5fs;

internal static class FileContent
{
    private const int BlockSize = VolumeGeometry.BlockSize;

    public static byte[] Read(BlockStore store, Inode inode)
    {
        byte[] content = new byte[inode.Size];
        int offset = 0;
        foreach (int block in inode.Extents.SelectMany(extent => extent.Blocks))
        {
            int count = Math.Min(BlockSize, content.Length - offset);
            store.Read(block)[..count].CopyTo(content.AsSpan(offset));
            offset += count;
        }

        return content;
    }

    /// <summary>Writes content into the extents, zero-filling the tail of the last block.</summary>
    public static void Write(BlockStore store, ImmutableArray<Extent> extents, ReadOnlySpan<byte> content)
    {
        int offset = 0;
        foreach (int block in extents.SelectMany(extent => extent.Blocks))
        {
            Span<byte> target = store.Write(block);
            int count = Math.Min(BlockSize, content.Length - offset);
            content.Slice(offset, count).CopyTo(target);
            target[count..].Clear();
            offset += count;
        }
    }

    public static int PhysicalBlock(Inode inode, int logicalBlock)
    {
        int remaining = logicalBlock;
        foreach (Extent extent in inode.Extents)
        {
            if (remaining < extent.Length)
            {
                return extent.Start + remaining;
            }

            remaining -= extent.Length;
        }

        throw new ArgumentOutOfRangeException(nameof(logicalBlock), logicalBlock, "Past the end of the inode's blocks.");
    }
}
