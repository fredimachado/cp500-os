namespace Cp500Os.C5x;

/// <summary>Memory limits the kernel loader applies to a program (design section 3 and 4).</summary>
public static class ArenaLimits
{
    public const int PageSize = 256;

    public const int ArenaPages = 158;

    /// <summary>Bytes the loader adds on top of every task stack for kernel and interrupt frames.</summary>
    public const int KernelStackReserve = 192;

    public const int ArenaBytes = ArenaPages * PageSize;
}
