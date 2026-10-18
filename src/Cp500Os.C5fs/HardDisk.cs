namespace Cp500Os.C5fs;

/// <summary>A raw hard disk image: block n at byte n * 256, block 0 the partition table.</summary>
public static class HardDisk
{
    /// <summary>
    /// Index i is slot i + 1, null an empty slot, at most four. Volumes go back to back from
    /// block 1 in slot order. Every volume must have partition geometry (Sides 0), else EINVAL.
    /// </summary>
    public static byte[] Build(IReadOnlyList<Volume?> partitions)
    {
        if (partitions.Count > PartitionTable.SlotCount)
        {
            throw new C5fsException(C5fsError.EINVAL, "at most four partitions");
        }

        List<PartitionEntry> entries = [];
        int cursor = 1;
        for (int i = 0; i < partitions.Count; i++)
        {
            Volume? volume = partitions[i];
            if (volume is null)
            {
                continue;
            }

            if (volume.Geometry.Sides != 0)
            {
                throw new C5fsException(C5fsError.EINVAL, "hard disk partitions need partition geometry");
            }

            int slot = i + 1;
            int count = volume.Geometry.BlockCount;
            entries.Add(new PartitionEntry(slot, cursor, count));
            cursor += count;
        }

        PartitionTable table = new(entries);
        int totalBlocks = cursor;
        byte[] disk = new byte[totalBlocks * VolumeGeometry.BlockSize];
        table.ToBlock().CopyTo(disk, 0);

        for (int i = 0; i < partitions.Count; i++)
        {
            Volume? volume = partitions[i];
            if (volume is null)
            {
                continue;
            }

            PartitionEntry entry = table.Find(i + 1)!;
            volume.ToImage().CopyTo(disk, entry.Start * VolumeGeometry.BlockSize);
        }

        return disk;
    }

    public static PartitionTable ReadTable(ReadOnlySpan<byte> disk)
    {
        if (disk.Length < VolumeGeometry.BlockSize)
        {
            throw new C5fsException(C5fsError.EIO, "disk image is too short for a partition table");
        }

        return PartitionTable.Parse(disk[..VolumeGeometry.BlockSize]);
    }

    public static Volume OpenPartition(ReadOnlySpan<byte> disk, int slot, TimeProvider? timeProvider = null)
    {
        PartitionTable table = ReadTable(disk);
        PartitionEntry? entry = table.Find(slot);
        if (entry is null)
        {
            throw new C5fsException(C5fsError.ENOENT, $"slot {slot} is empty");
        }

        int offset = entry.Start * VolumeGeometry.BlockSize;
        int length = entry.Count * VolumeGeometry.BlockSize;
        if (offset + length > disk.Length)
        {
            throw new C5fsException(C5fsError.EIO, "partition extends past the image end");
        }

        return Volume.Open(disk.Slice(offset, length), timeProvider);
    }

    public static void WritePartition(Span<byte> disk, int slot, Volume volume)
    {
        PartitionTable table = ReadTable(disk);
        PartitionEntry? entry = table.Find(slot);
        if (entry is null)
        {
            throw new C5fsException(C5fsError.ENOENT, $"slot {slot} is empty");
        }

        byte[] image = volume.ToImage();
        if (image.Length != entry.Count * VolumeGeometry.BlockSize)
        {
            throw new C5fsException(C5fsError.EINVAL, "volume size does not match the partition");
        }

        image.CopyTo(disk.Slice(entry.Start * VolumeGeometry.BlockSize));
    }
}
