using System.Buffers.Binary;

namespace Cp500Os.C5fs;

/// <summary>One copy of the superblock (blocks 1 and 2). Layout in design section 7.</summary>
public sealed record Superblock
{
    public const byte CurrentVersion = 1;
    public const int LabelLength = 16;
    public const int CrcOffset = 254;

    private const byte CleanFlag = 0x01;

    private readonly string _label = "";

    public static ReadOnlySpan<byte> Magic => "C5FS"u8;

    public required VolumeGeometry Geometry { get; init; }

    public required uint VolumeId { get; init; }

    /// <summary>The copy with the higher sequence wins.</summary>
    public required uint Sequence { get; init; }

    /// <summary>Incremented each time the volume goes from clean to dirty, so a kernel sees a host edit as a disk change.</summary>
    public required ushort Generation { get; init; }

    public required bool Clean { get; init; }

    /// <summary>The kernel's single contiguous run, or null when no kernel is installed.</summary>
    public required Extent? Kernel { get; init; }

    public required C5Time Created { get; init; }

    public required C5Time LastWritten { get; init; }

    /// <summary>Up to 16 printable ISO-8859-1 characters.</summary>
    public string Label
    {
        get => _label;
        init => _label = ValidateLabel(value);
    }

    /// <summary>True when the block starts with the magic and its CRC matches.</summary>
    public static bool IsValidCopy(ReadOnlySpan<byte> block) =>
        block.Length == VolumeGeometry.BlockSize
        && block.StartsWith(Magic)
        && BinaryPrimitives.ReadUInt16LittleEndian(block[CrcOffset..]) == Crc16Ccitt.Compute(block[..CrcOffset]);

    /// <summary>Parses a copy that passed <see cref="IsValidCopy"/>; throws EIO when its contents are inconsistent.</summary>
    public static Superblock Parse(ReadOnlySpan<byte> block)
    {
        if (!IsValidCopy(block))
        {
            throw Corrupt("bad magic or CRC");
        }

        if (block[4] != CurrentVersion)
        {
            throw Corrupt($"version {block[4]} is not supported (expected {CurrentVersion})");
        }

        if ((block[5] & ~CleanFlag) != 0)
        {
            throw Corrupt($"unknown flags 0x{block[5]:X2}");
        }

        VolumeGeometry geometry;
        try
        {
            geometry = VolumeGeometry.Create(
                U16(block, 16), U16(block, 23), block[27], block[28], block[29]);
        }
        catch (C5fsException e)
        {
            throw Corrupt(e.Message);
        }

        if (U16(block, 18) != VolumeGeometry.BitmapStart
            || block[20] != geometry.BitmapLength
            || U16(block, 21) != geometry.InodeTableStart
            || U16(block, 25) != geometry.FirstDataBlock)
        {
            throw Corrupt("layout fields do not match the block and inode counts");
        }

        Extent? kernel = ParseKernel(U16(block, 30), U16(block, 32), geometry);
        string label = ParseLabel(block.Slice(42, LabelLength));

        return new Superblock
        {
            Geometry = geometry,
            Clean = (block[5] & CleanFlag) != 0,
            Sequence = BinaryPrimitives.ReadUInt32LittleEndian(block[6..]),
            VolumeId = BinaryPrimitives.ReadUInt32LittleEndian(block[10..]),
            Generation = U16(block, 14),
            Kernel = kernel,
            Created = new C5Time(BinaryPrimitives.ReadUInt32LittleEndian(block[34..])),
            LastWritten = new C5Time(BinaryPrimitives.ReadUInt32LittleEndian(block[38..])),
            Label = label,
        };
    }

    public byte[] Serialize()
    {
        byte[] block = new byte[VolumeGeometry.BlockSize];
        Span<byte> span = block;
        Magic.CopyTo(span);
        span[4] = CurrentVersion;
        span[5] = Clean ? CleanFlag : (byte)0;
        BinaryPrimitives.WriteUInt32LittleEndian(span[6..], Sequence);
        BinaryPrimitives.WriteUInt32LittleEndian(span[10..], VolumeId);
        BinaryPrimitives.WriteUInt16LittleEndian(span[14..], Generation);
        BinaryPrimitives.WriteUInt16LittleEndian(span[16..], Geometry.BlockCount);
        BinaryPrimitives.WriteUInt16LittleEndian(span[18..], VolumeGeometry.BitmapStart);
        span[20] = Geometry.BitmapLength;
        BinaryPrimitives.WriteUInt16LittleEndian(span[21..], Geometry.InodeTableStart);
        BinaryPrimitives.WriteUInt16LittleEndian(span[23..], Geometry.InodeCount);
        BinaryPrimitives.WriteUInt16LittleEndian(span[25..], Geometry.FirstDataBlock);
        span[27] = Geometry.Sides;
        span[28] = Geometry.Tracks;
        span[29] = Geometry.SectorsPerTrack;
        BinaryPrimitives.WriteUInt16LittleEndian(span[30..], Kernel?.Start ?? 0);
        BinaryPrimitives.WriteUInt16LittleEndian(span[32..], Kernel?.Length ?? 0);
        BinaryPrimitives.WriteUInt32LittleEndian(span[34..], Created.Seconds);
        BinaryPrimitives.WriteUInt32LittleEndian(span[38..], LastWritten.Seconds);
        Latin1Text.Encode(Label, "label").CopyTo(span[42..]);
        BinaryPrimitives.WriteUInt16LittleEndian(span[CrcOffset..], Crc16Ccitt.Compute(span[..CrcOffset]));
        return block;
    }

    private static Extent? ParseKernel(ushort start, ushort count, VolumeGeometry geometry)
    {
        if (count == 0)
        {
            return start == 0 ? null : throw Corrupt($"kernel start {start} with a block count of 0");
        }

        if (count > Extent.MaxLength || start < geometry.FirstDataBlock || start + count > geometry.BlockCount)
        {
            throw Corrupt($"kernel run of {count} blocks at {start} is not a valid single extent in the data area");
        }

        return new Extent(start, count);
    }

    private static string ParseLabel(ReadOnlySpan<byte> field)
    {
        int length = field.IndexOf((byte)0);
        if (length < 0)
        {
            length = field.Length;
        }

        if (field[length..].ContainsAnyExcept((byte)0) || !field[..length].ToArray().All(Latin1Text.IsPrintable))
        {
            throw Corrupt("label is not NUL-padded printable ISO-8859-1");
        }

        return Latin1Text.Decode(field[..length]);
    }

    private static string ValidateLabel(string label)
    {
        ArgumentNullException.ThrowIfNull(label);
        byte[] bytes = Latin1Text.Encode(label, "label");
        if (bytes.Length > LabelLength)
        {
            throw new C5fsException(C5fsError.EINVAL, $"label '{label}' is {bytes.Length} bytes, the limit is {LabelLength}");
        }

        return bytes.All(Latin1Text.IsPrintable)
            ? Latin1Text.Decode(bytes)
            : throw new C5fsException(C5fsError.EINVAL, $"label '{label}' contains a non-printable character");
    }

    private static ushort U16(ReadOnlySpan<byte> block, int offset) => BinaryPrimitives.ReadUInt16LittleEndian(block[offset..]);

    private static C5fsException Corrupt(string message) => new(C5fsError.EIO, $"superblock: {message}");
}
