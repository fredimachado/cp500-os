namespace Cp500Os.C5x;

/// <summary>A relocatable program: header, image linked at 0000h, and its relocation bitmap.</summary>
public sealed class C5xProgram
{
    private readonly byte[] _image;

    public C5xProgram(C5xHeader header, ReadOnlySpan<byte> image, RelocationBitmap relocations)
    {
        ArgumentNullException.ThrowIfNull(header);
        ArgumentNullException.ThrowIfNull(relocations);
        if (image.Length != header.ImageSize)
            throw new ArgumentException($"The header declares {header.ImageSize} image bytes but the image has {image.Length}.", nameof(image));
        if (relocations.Length != image.Length)
            throw new ArgumentException($"The bitmap covers {relocations.Length} bytes but the image has {image.Length}.", nameof(relocations));

        Header = header;
        _image = image.ToArray();
        Relocations = relocations;
    }

    public C5xHeader Header { get; }

    /// <summary>The image as linked at 0000h.</summary>
    public ReadOnlySpan<byte> Image => _image;

    public RelocationBitmap Relocations { get; }

    /// <summary>Builds a program from the same code linked at 0000h and at 0100h.</summary>
    public static C5xProgram FromLinks(
        ReadOnlySpan<byte> link0000,
        ReadOnlySpan<byte> link0100,
        ushort bssSize,
        ushort stackSize,
        ushort entryOffset)
    {
        var relocations = RelocationBitmap.FromLinks(link0000, link0100);
        if (link0000.Length > ushort.MaxValue)
            throw new C5xException(new ProgramTooLarge(link0000.Length, bssSize, stackSize));

        var header = new C5xHeader((ushort)link0000.Length, bssSize, stackSize, entryOffset);
        return new C5xProgram(header, link0000, relocations);
    }

    /// <summary>The image as the loader leaves it at <c>loadPage * 256</c>.</summary>
    public byte[] RelocateTo(byte loadPage) => Relocator.Relocate(_image, Relocations, loadPage);
}
