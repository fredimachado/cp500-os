namespace Cp500Os.C5fs;

public sealed record FormatOptions
{
    public VolumeGeometry Geometry { get; init; } = VolumeGeometry.Floppy360;

    public string Label { get; init; } = "";

    /// <summary>Random when null.</summary>
    public uint? VolumeId { get; init; }

    public TimeProvider TimeProvider { get; init; } = TimeProvider.System;
}

/// <summary>The two superblock copies; the value is the block number.</summary>
public enum SuperblockCopy
{
    A = 1,
    B = 2,
}
