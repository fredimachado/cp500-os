namespace Cp500Os.C5x;

/// <summary>
/// The sizes and entry point of a C5X program. Construction guarantees the entry point lies inside
/// the image and that image, bss, stack and the kernel stack reserve fit in the arena.
/// </summary>
public sealed record C5xHeader
{
    public C5xHeader(ushort imageSize, ushort bssSize, ushort stackSize, ushort entryOffset)
    {
        if (imageSize + bssSize + stackSize + ArenaLimits.KernelStackReserve > ArenaLimits.ArenaBytes)
            throw new C5xException(new ProgramTooLarge(imageSize, bssSize, stackSize));
        if (entryOffset >= imageSize)
            throw new C5xException(new EntryOutsideImage(entryOffset, imageSize));

        ImageSize = imageSize;
        BssSize = bssSize;
        StackSize = stackSize;
        EntryOffset = entryOffset;
    }

    public ushort ImageSize { get; }

    public ushort BssSize { get; }

    /// <summary>Stack the program needs, without the kernel reserve the loader adds.</summary>
    public ushort StackSize { get; }

    public ushort EntryOffset { get; }

    /// <summary>Bytes the loader allocates: image, bss, stack and the kernel stack reserve.</summary>
    public int MemoryBytes => ImageSize + BssSize + StackSize + ArenaLimits.KernelStackReserve;

    public int MemoryPages => (MemoryBytes + ArenaLimits.PageSize - 1) / ArenaLimits.PageSize;
}
