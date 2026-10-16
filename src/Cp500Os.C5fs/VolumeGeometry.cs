namespace Cp500Os.C5fs;

/// <summary>Size and floppy geometry of a volume, and the metadata layout that follows from them.</summary>
public sealed record VolumeGeometry
{
    public const int BlockSize = 256;
    public const int BitmapStart = 3;
    public const int InodesPerBlock = BlockSize / Inode.RecordSize;
    public const int BitsPerBitmapBlock = BlockSize * 8;

    private VolumeGeometry(int blockCount, int inodeCount, int sides, int tracks, int sectorsPerTrack)
    {
        if (blockCount is < 1 or > ushort.MaxValue)
        {
            throw Invalid($"block count {blockCount} is outside 1-{ushort.MaxValue}");
        }

        if (inodeCount < InodesPerBlock || inodeCount % InodesPerBlock != 0 || inodeCount > ushort.MaxValue)
        {
            throw Invalid($"inode count {inodeCount} must be a positive multiple of {InodesPerBlock}");
        }

        if (sides == 0 ? tracks != 0 || sectorsPerTrack != 0 : sides > 2 || sides * tracks * sectorsPerTrack != blockCount)
        {
            throw Invalid($"geometry {sides} sides x {tracks} tracks x {sectorsPerTrack} sectors does not match {blockCount} blocks");
        }

        BlockCount = (ushort)blockCount;
        InodeCount = (ushort)inodeCount;
        Sides = (byte)sides;
        Tracks = (byte)tracks;
        SectorsPerTrack = (byte)sectorsPerTrack;

        int firstData = BitmapStart + BitmapLength + (inodeCount / InodesPerBlock);
        if (firstData >= blockCount)
        {
            throw Invalid($"{blockCount} blocks leave no room for data after {firstData} metadata blocks");
        }
    }

    /// <summary>180 KiB floppy: 1 side, 40 tracks, 18 sectors, 64 inodes.</summary>
    public static VolumeGeometry Floppy180 { get; } = new(720, 64, 1, 40, 18);

    /// <summary>360 KiB floppy: 2 sides, 40 tracks, 18 sectors, 128 inodes.</summary>
    public static VolumeGeometry Floppy360 { get; } = new(1440, 128, 2, 40, 18);

    public ushort BlockCount { get; }

    /// <summary>Inode table slots. Slot 0 is reserved, so inodes 1 to InodeCount-1 are usable.</summary>
    public ushort InodeCount { get; }

    /// <summary>Floppy sides, 0 on a hard disk partition.</summary>
    public byte Sides { get; }

    public byte Tracks { get; }

    public byte SectorsPerTrack { get; }

    public byte BitmapLength => (byte)((BlockCount + BitsPerBitmapBlock - 1) / BitsPerBitmapBlock);

    public ushort InodeTableStart => (ushort)(BitmapStart + BitmapLength);

    public ushort InodeTableLength => (ushort)(InodeCount / InodesPerBlock);

    public ushort FirstDataBlock => (ushort)(InodeTableStart + InodeTableLength);

    public int ImageSize => BlockCount * BlockSize;

    public static VolumeGeometry Partition(int blockCount, int inodeCount) => new(blockCount, inodeCount, 0, 0, 0);

    internal static VolumeGeometry Create(int blockCount, int inodeCount, int sides, int tracks, int sectorsPerTrack) =>
        new(blockCount, inodeCount, sides, tracks, sectorsPerTrack);

    private static C5fsException Invalid(string message) => new(C5fsError.EINVAL, message);
}
