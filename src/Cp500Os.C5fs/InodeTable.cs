using System.Buffers.Binary;
using System.Collections.Immutable;

namespace Cp500Os.C5fs;

internal sealed record InodeRecord(Inode Inode, ushort? IndirectBlock);

/// <summary>
/// The inode table. Slot n holds inode n; slot 0 is reserved. A free slot is all zero bytes.
/// Layout of a slot and of the indirect block is in design section 7.
/// </summary>
internal sealed class InodeTable(BlockStore store, VolumeGeometry geometry, BlockAllocator allocator)
{
    public const ushort RootNumber = 1;

    private const int KindMask = 0x0F;
    private const int AttributeMask = 0x30;
    private const int IndirectBit = 0x40;
    private const int ExtentsOffset = 13;
    private const int ExtentSize = 3;
    private const int InlineWithIndirect = Inode.InlineExtents - 1;
    private const int IndirectPointerOffset = ExtentsOffset + (InlineWithIndirect * ExtentSize);

    public ReadOnlySpan<byte> RawSlot(int number) =>
        store.Read(BlockOf(number)).Slice(OffsetOf(number), Inode.RecordSize);

    public bool IsFree(int number) => RawSlot(number)[0] == 0;

    /// <summary>Reads an inode, or null for a free slot. Throws EIO when the slot or its indirect block is malformed.</summary>
    public InodeRecord? Read(int number)
    {
        if (number is < RootNumber || number >= geometry.InodeCount)
        {
            throw new C5fsException(C5fsError.EIO, $"inode {number} is outside 1-{geometry.InodeCount - 1}");
        }

        ReadOnlySpan<byte> slot = RawSlot(number);
        if (slot[0] == 0)
        {
            return null;
        }

        try
        {
            return Decode(number, slot);
        }
        catch (ArgumentException e)
        {
            throw Corrupt(number, e.Message);
        }
    }

    public Inode Get(int number) =>
        Read(number)?.Inode ?? throw new C5fsException(C5fsError.EIO, $"inode {number} is referenced but free");

    public ushort Allocate()
    {
        for (int number = RootNumber; number < geometry.InodeCount; number++)
        {
            if (IsFree(number))
            {
                return (ushort)number;
            }
        }

        throw new C5fsException(C5fsError.ENOSPC, $"no free inodes (all {geometry.InodeCount - 1} are in use)");
    }

    public int CountFree()
    {
        int free = 0;
        for (int number = RootNumber; number < geometry.InodeCount; number++)
        {
            free += IsFree(number) ? 1 : 0;
        }

        return free;
    }

    /// <summary>Stores an inode, allocating, keeping or freeing its indirect block as the extent count requires.</summary>
    public void Write(int number, Inode inode)
    {
        ushort? indirect = Read(number)?.IndirectBlock;
        if (inode.NeedsIndirectBlock)
        {
            indirect ??= allocator.AllocateContiguous(1).Start;
        }
        else if (indirect is ushort unused)
        {
            allocator.Free([new Extent(unused, 1)]);
            indirect = null;
        }

        Span<byte> slot = store.Write(BlockOf(number)).Slice(OffsetOf(number), Inode.RecordSize);
        slot.Clear();
        slot[0] = (byte)((byte)inode.Kind | (byte)inode.Attributes | (indirect is null ? 0 : IndirectBit));
        slot[1] = (byte)inode.Extents.Length;
        slot[2] = (byte)inode.Size;
        slot[3] = (byte)(inode.Size >> 8);
        slot[4] = (byte)(inode.Size >> 16);
        BinaryPrimitives.WriteUInt32LittleEndian(slot[5..], inode.Modified.Seconds);
        BinaryPrimitives.WriteUInt32LittleEndian(slot[9..], inode.Created.Seconds);

        int inline = indirect is null ? inode.Extents.Length : InlineWithIndirect;
        for (int i = 0; i < inline; i++)
        {
            WriteExtent(slot[(ExtentsOffset + (i * ExtentSize))..], inode.Extents[i]);
        }

        if (indirect is ushort block)
        {
            BinaryPrimitives.WriteUInt16LittleEndian(slot[IndirectPointerOffset..], block);
            Span<byte> spill = store.Write(block);
            spill.Clear();
            for (int i = inline; i < inode.Extents.Length; i++)
            {
                WriteExtent(spill[((i - inline) * ExtentSize)..], inode.Extents[i]);
            }
        }
    }

    /// <summary>Frees the inode's data blocks and indirect block and zeroes its slot.</summary>
    public void Release(int number)
    {
        InodeRecord record = Read(number) ?? throw new InvalidOperationException($"Inode {number} is already free.");
        allocator.Free(record.Inode.Extents);
        if (record.IndirectBlock is ushort block)
        {
            allocator.Free([new Extent(block, 1)]);
        }

        store.Write(BlockOf(number)).Slice(OffsetOf(number), Inode.RecordSize).Clear();
    }

    private InodeRecord Decode(int number, ReadOnlySpan<byte> slot)
    {
        byte type = slot[0];
        InodeKind kind = (InodeKind)(type & KindMask);
        if (!Enum.IsDefined(kind))
        {
            throw Corrupt(number, $"unknown type {type & KindMask}");
        }

        if ((type & ~(KindMask | AttributeMask | IndirectBit)) != 0 || slot[Inode.RecordSize - 1] != 0)
        {
            throw Corrupt(number, "reserved bits are set");
        }

        int count = slot[1];
        bool indirect = (type & IndirectBit) != 0;
        if (indirect ? count is <= Inode.InlineExtents or > Inode.MaxExtents : count > Inode.InlineExtents)
        {
            throw Corrupt(number, $"extent count {count} does not match the indirect flag");
        }

        ImmutableArray<Extent>.Builder extents = ImmutableArray.CreateBuilder<Extent>(count);
        ushort? indirectBlock = null;
        if (indirect)
        {
            ReadExtents(number, slot[ExtentsOffset..IndirectPointerOffset], InlineWithIndirect, extents);
            ushort block = BinaryPrimitives.ReadUInt16LittleEndian(slot[IndirectPointerOffset..]);
            byte lengthByte = slot[IndirectPointerOffset + 2];
            if (lengthByte != 0 || block < geometry.FirstDataBlock || block >= geometry.BlockCount)
            {
                throw Corrupt(number, $"indirect pointer {block} (length byte {lengthByte}) is not a data block with length 0");
            }

            indirectBlock = block;
            ReadExtents(number, store.Read(block), count - InlineWithIndirect, extents);
        }
        else
        {
            ReadExtents(number, slot[ExtentsOffset..(Inode.RecordSize - 1)], count, extents);
        }

        int size = slot[2] | (slot[3] << 8) | (slot[4] << 16);
        Inode inode = new(
            kind,
            (InodeAttributes)(type & AttributeMask),
            size,
            new C5Time(BinaryPrimitives.ReadUInt32LittleEndian(slot[5..])),
            new C5Time(BinaryPrimitives.ReadUInt32LittleEndian(slot[9..])),
            extents.MoveToImmutable());
        return new InodeRecord(inode, indirectBlock);
    }

    /// <summary>Reads <paramref name="used"/> packed extents and requires every byte after them to be zero.</summary>
    private void ReadExtents(int number, ReadOnlySpan<byte> area, int used, ImmutableArray<Extent>.Builder extents)
    {
        for (int i = 0; i < used; i++)
        {
            extents.Add(ReadExtent(number, area[(i * ExtentSize)..]));
        }

        if (area[(used * ExtentSize)..].ContainsAnyExcept((byte)0))
        {
            throw Corrupt(number, "unused extent bytes are not zero");
        }
    }

    private Extent ReadExtent(int number, ReadOnlySpan<byte> bytes)
    {
        int start = BinaryPrimitives.ReadUInt16LittleEndian(bytes);
        int length = bytes[2];
        return length != 0 && start >= geometry.FirstDataBlock && start + length <= geometry.BlockCount
            ? new Extent(start, length)
            : throw Corrupt(number, $"extent {start}+{length} is not inside the data area");
    }

    private static void WriteExtent(Span<byte> bytes, Extent extent)
    {
        BinaryPrimitives.WriteUInt16LittleEndian(bytes, extent.Start);
        bytes[2] = extent.Length;
    }

    private int BlockOf(int number) => geometry.InodeTableStart + (number / VolumeGeometry.InodesPerBlock);

    private static int OffsetOf(int number) => number % VolumeGeometry.InodesPerBlock * Inode.RecordSize;

    private static C5fsException Corrupt(int number, string message) => new(C5fsError.EIO, $"inode {number}: {message}");
}
