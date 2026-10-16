using System.Buffers.Binary;

namespace Cp500Os.C5x;

/// <summary>Reads and writes the C5X file layout (design section 6, "Program format and loading").</summary>
public static class C5xFile
{
    public const byte Version = 1;

    public const int HeaderSize = 16;

    private const int MagicOffset = 0;
    private const int VersionOffset = 3;
    private const int ImageSizeOffset = 4;
    private const int BssSizeOffset = 6;
    private const int StackSizeOffset = 8;
    private const int EntryOffsetOffset = 10;
    private const int ReservedOffset = 12;
    private const int ReservedSize = 4;

    public static ReadOnlySpan<byte> Magic => "C5X"u8;

    public static int FileSize(int imageSize) => HeaderSize + imageSize + RelocationBitmap.ByteCount(imageSize);

    public static byte[] Write(C5xProgram program)
    {
        ArgumentNullException.ThrowIfNull(program);
        var header = program.Header;
        var file = new byte[FileSize(header.ImageSize)];
        var span = file.AsSpan();

        Magic.CopyTo(span[MagicOffset..]);
        span[VersionOffset] = Version;
        BinaryPrimitives.WriteUInt16LittleEndian(span[ImageSizeOffset..], header.ImageSize);
        BinaryPrimitives.WriteUInt16LittleEndian(span[BssSizeOffset..], header.BssSize);
        BinaryPrimitives.WriteUInt16LittleEndian(span[StackSizeOffset..], header.StackSize);
        BinaryPrimitives.WriteUInt16LittleEndian(span[EntryOffsetOffset..], header.EntryOffset);
        program.Image.CopyTo(span[HeaderSize..]);
        program.Relocations.Bytes.CopyTo(span[(HeaderSize + header.ImageSize)..]);
        return file;
    }

    public static C5xProgram Parse(ReadOnlySpan<byte> file)
    {
        if (file.Length < HeaderSize)
            throw new C5xException(new Truncated(HeaderSize, file.Length));
        if (!file[..Magic.Length].SequenceEqual(Magic))
            throw new C5xException(new BadMagic(file[0], file[1], file[2]));
        if (file[VersionOffset] != Version)
            throw new C5xException(new UnsupportedVersion(file[VersionOffset]));
        if (file.Slice(ReservedOffset, ReservedSize).ContainsAnyExcept((byte)0))
            throw new C5xException(new ReservedNotZero());

        ushort imageSize = BinaryPrimitives.ReadUInt16LittleEndian(file[ImageSizeOffset..]);
        int expected = FileSize(imageSize);
        if (file.Length < expected)
            throw new C5xException(new Truncated(expected, file.Length));
        if (file.Length > expected)
            throw new C5xException(new TrailingData(expected, file.Length));

        var header = new C5xHeader(
            imageSize,
            BinaryPrimitives.ReadUInt16LittleEndian(file[BssSizeOffset..]),
            BinaryPrimitives.ReadUInt16LittleEndian(file[StackSizeOffset..]),
            BinaryPrimitives.ReadUInt16LittleEndian(file[EntryOffsetOffset..]));
        var image = file.Slice(HeaderSize, imageSize);
        var relocations = RelocationBitmap.FromBytes(file[(HeaderSize + imageSize)..], imageSize);
        return new C5xProgram(header, image, relocations);
    }
}
