using System.Buffers.Binary;

namespace Cp500Os.C5fs;

/// <summary>
/// Disk block 0: four 7-byte entries at 7 * (slot - 1), type then 24-bit LE start and count.
/// Type 0 with zeros is an empty slot, type 1 is C5FS, bytes 28-255 are zero.
/// kernel/hd.asm reads the same bytes.
/// </summary>
public sealed class PartitionTable
{
    public const int SlotCount = 4;
    public const int EntrySize = 7;
    public const byte EmptyType = 0;
    public const byte C5fsType = 1;
    public const int BlockLimit = 1 << 24;

    private readonly PartitionEntry[] _entries;

    public PartitionTable(IEnumerable<PartitionEntry> entries)
    {
        ArgumentNullException.ThrowIfNull(entries);
        PartitionEntry[] list = entries.OrderBy(e => e.Slot).ToArray();
        if (list.Length > SlotCount)
        {
            throw Invalid("at most four partitions");
        }

        HashSet<int> slots = [];
        int? cursor = null;
        foreach (PartitionEntry entry in list)
        {
            if (entry.Slot is < 1 or > SlotCount)
            {
                throw Invalid($"slot {entry.Slot} is outside 1-{SlotCount}");
            }

            if (!slots.Add(entry.Slot))
            {
                throw Invalid($"duplicate slot {entry.Slot}");
            }

            if (entry.Start < 1)
            {
                throw Invalid($"slot {entry.Slot} start {entry.Start} must be at least 1");
            }

            if (entry.Count is < 1 or > ushort.MaxValue)
            {
                throw Invalid($"slot {entry.Slot} count {entry.Count} is outside 1-{ushort.MaxValue}");
            }

            if (entry.End > BlockLimit)
            {
                throw Invalid($"slot {entry.Slot} end {entry.End} exceeds {BlockLimit}");
            }

            if (cursor is not null && entry.Start < cursor)
            {
                throw Invalid("partition ranges overlap");
            }

            cursor = entry.End;
        }

        _entries = list;
    }

    public IReadOnlyList<PartitionEntry> Entries => _entries;

    public PartitionEntry? Find(int slot) => _entries.FirstOrDefault(e => e.Slot == slot);

    public static PartitionTable Parse(ReadOnlySpan<byte> block)
    {
        if (block.Length < 256)
        {
            throw new C5fsException(C5fsError.EIO, "partition table block is too short");
        }

        List<PartitionEntry> entries = [];
        for (int slot = 1; slot <= SlotCount; slot++)
        {
            int off = EntrySize * (slot - 1);
            byte type = block[off];
            int start = ReadLe24(block, off + 1);
            int count = ReadLe24(block, off + 4);
            if (type == EmptyType)
            {
                if (block.Slice(off, EntrySize).ContainsAnyExcept((byte)0))
                {
                    throw new C5fsException(C5fsError.EIO, $"slot {slot} is not an empty entry");
                }

                continue;
            }

            if (type != C5fsType)
            {
                throw new C5fsException(C5fsError.EIO, $"slot {slot} has unknown type {type}");
            }

            if (start < 1 || count < 1 || count > ushort.MaxValue || start + count > BlockLimit)
            {
                throw new C5fsException(C5fsError.EIO, $"slot {slot} has an invalid range");
            }

            foreach (PartitionEntry existing in entries)
            {
                if (RangesOverlap(existing.Start, existing.End, start, start + count))
                {
                    throw new C5fsException(C5fsError.EIO, "partition ranges overlap");
                }
            }

            entries.Add(new PartitionEntry(slot, start, count));
        }

        if (block.Slice(28, 256 - 28).ContainsAnyExcept((byte)0))
        {
            throw new C5fsException(C5fsError.EIO, "partition table tail must be zero");
        }

        return new PartitionTable(entries);
    }

    public byte[] ToBlock()
    {
        byte[] block = new byte[256];
        foreach (PartitionEntry entry in _entries)
        {
            int off = EntrySize * (entry.Slot - 1);
            block[off] = C5fsType;
            WriteLe24(block, off + 1, entry.Start);
            WriteLe24(block, off + 4, entry.Count);
        }

        return block;
    }

    private static bool RangesOverlap(int aStart, int aEnd, int bStart, int bEnd) =>
        aStart < bEnd && bStart < aEnd;

    private static int ReadLe24(ReadOnlySpan<byte> data, int offset) =>
        data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16);

    private static void WriteLe24(byte[] data, int offset, int value)
    {
        data[offset] = (byte)value;
        data[offset + 1] = (byte)(value >> 8);
        data[offset + 2] = (byte)(value >> 16);
    }

    private static C5fsException Invalid(string message) => new(C5fsError.EINVAL, message);
}
