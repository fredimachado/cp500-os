namespace Cp500Os.C5fs;

/// <summary>A C5FS partition in the hard disk table. Slot 1-4, block range on the disk.</summary>
public sealed record PartitionEntry(int Slot, int Start, int Count)
{
    public int End => Start + Count;
}
