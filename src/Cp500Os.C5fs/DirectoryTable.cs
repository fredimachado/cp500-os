using System.Buffers.Binary;

namespace Cp500Os.C5fs;

/// <summary>One 32-byte directory entry as stored: inode number (0 = free) and the raw 30-byte name field.</summary>
internal sealed record DirectorySlot(int Index, ushort InodeNumber, ReadOnlyMemory<byte> NameField)
{
    public bool IsFree => InodeNumber == 0;

    public bool IsZeroed => IsFree && !NameField.Span.ContainsAnyExcept((byte)0);

    public bool HasParentName =>
        NameField.Span.StartsWith(DirectoryTable.ParentName)
        && !NameField.Span[DirectoryTable.ParentName.Length..].ContainsAnyExcept((byte)0);

    public FileName? Name => FileName.TryDecode(NameField.Span);
}

/// <summary>
/// Directory contents: 32-byte entries, the first always ".." (the root's points at itself).
/// Removing an entry zeroes it; free entries are reused before the directory grows.
/// </summary>
internal sealed class DirectoryTable(BlockStore store, InodeTable inodes, BlockAllocator allocator)
{
    private const int EntrySize = Inode.DirectoryEntrySize;
    private const int EntriesPerBlock = VolumeGeometry.BlockSize / EntrySize;

    public static ReadOnlySpan<byte> ParentName => ".."u8;

    public IReadOnlyList<DirectorySlot> ReadSlots(Inode directory)
    {
        byte[] content = FileContent.Read(store, directory);
        DirectorySlot[] slots = new DirectorySlot[content.Length / EntrySize];
        for (int i = 0; i < slots.Length; i++)
        {
            ReadOnlyMemory<byte> entry = content.AsMemory(i * EntrySize, EntrySize);
            slots[i] = new DirectorySlot(i, BinaryPrimitives.ReadUInt16LittleEndian(entry.Span), entry[2..]);
        }

        return slots;
    }

    /// <summary>The used entries after "..", with their names. Throws EIO on an undecodable name.</summary>
    public IEnumerable<(DirectorySlot Slot, FileName Name)> Entries(Inode directory) =>
        ReadSlots(directory)
            .Skip(1)
            .Where(slot => !slot.IsFree)
            .Select(slot => (slot, slot.Name ?? throw new C5fsException(
                C5fsError.EIO, $"directory entry {slot.Index} for inode {slot.InodeNumber} has an invalid name")));

    public DirectorySlot? Find(Inode directory, FileName name) =>
        Entries(directory).Where(entry => entry.Name == name).Select(entry => entry.Slot).FirstOrDefault();

    /// <summary>Allocates and fills the first block of a new directory: just "..".</summary>
    public Extent CreateEmpty(ushort parent)
    {
        Extent block = allocator.AllocateContiguous(1);
        Span<byte> data = store.Write(block.Start);
        data.Clear();
        BinaryPrimitives.WriteUInt16LittleEndian(data, parent);
        ParentName.CopyTo(data[2..]);
        return block;
    }

    public void Add(int directoryNumber, FileName name, ushort child, C5Time now)
    {
        Inode directory = inodes.Get(directoryNumber);
        int index = ReadSlots(directory).Skip(1).FirstOrDefault(slot => slot.IsFree)?.Index
            ?? directory.Size / EntrySize;

        if (index == directory.Size / EntrySize)
        {
            int size = directory.Size + EntrySize;
            directory = Inode.BlocksFor(size) > directory.BlockCount
                ? directory.WithContent(size, allocator.Grow(directory.Extents, 1), now)
                : directory.WithContent(size, directory.Extents, now);
            if (index % EntriesPerBlock == 0)
            {
                store.Write(FileContent.PhysicalBlock(directory, index / EntriesPerBlock)).Clear();
            }
        }
        else
        {
            directory = directory.WithModified(now);
        }

        Span<byte> entry = EntryBytes(directory, index);
        BinaryPrimitives.WriteUInt16LittleEndian(entry, child);
        name.EncodeTo(entry[2..]);
        inodes.Write(directoryNumber, directory);
    }

    public void Remove(int directoryNumber, int index, C5Time now)
    {
        Inode directory = inodes.Get(directoryNumber);
        EntryBytes(directory, index).Clear();
        inodes.Write(directoryNumber, directory.WithModified(now));
    }

    /// <summary>Points the directory's <c>..</c> entry at <paramref name="parent"/>.</summary>
    public void SetParent(int directoryNumber, ushort parent, C5Time now)
    {
        Inode directory = inodes.Get(directoryNumber);
        BinaryPrimitives.WriteUInt16LittleEndian(EntryBytes(directory, 0), parent);
        inodes.Write(directoryNumber, directory.WithModified(now));
    }

    private Span<byte> EntryBytes(Inode directory, int index) =>
        store.Write(FileContent.PhysicalBlock(directory, index / EntriesPerBlock))
            .Slice(index % EntriesPerBlock * EntrySize, EntrySize);
}
