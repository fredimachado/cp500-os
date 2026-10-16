using System.Globalization;

namespace Cp500Os.C5x;

/// <summary>Why a pair of links or a C5X file cannot become a <see cref="C5xProgram"/>.</summary>
public abstract record C5xError
{
    public abstract string Message { get; }

    private protected static string Hex(int value) => value.ToString("X4", CultureInfo.InvariantCulture) + "h";
}

public sealed record LinkLengthMismatch(int Length0000, int Length0100) : C5xError
{
    public override string Message =>
        $"The two links differ in length: {Length0000} bytes at 0000h, {Length0100} bytes at 0100h.";
}

/// <summary>A byte at the same offset in both links that is neither equal nor exactly 1 higher in the 0100h link.</summary>
public sealed record LinkDifference(int Offset, byte At0000, byte At0100);

public sealed record NonRelocatableDifferences(IReadOnlyList<LinkDifference> Differences) : C5xError
{
    public const int ReportedLimit = 8;

    public override string Message
    {
        get
        {
            var shown = Differences.Take(ReportedLimit).Select(d =>
                string.Create(CultureInfo.InvariantCulture, $"{Hex(d.Offset)} ({d.At0000:X2}h -> {d.At0100:X2}h)"));
            string more = Differences.Count > ReportedLimit ? $", and {Differences.Count - ReportedLimit} more" : "";
            return $"{Differences.Count} byte(s) differ between the links by something other than +1: "
                + string.Join(", ", shown) + more + ".";
        }
    }

    public bool Equals(NonRelocatableDifferences? other) =>
        other is not null && Differences.SequenceEqual(other.Differences);

    public override int GetHashCode() => Differences.Count;
}

public sealed record EntryOutsideImage(int EntryOffset, int ImageSize) : C5xError
{
    public override string Message => $"Entry offset {Hex(EntryOffset)} is outside the {ImageSize}-byte image.";
}

public sealed record ProgramTooLarge(int ImageSize, int BssSize, int StackSize) : C5xError
{
    public int RequiredBytes => ImageSize + BssSize + StackSize + ArenaLimits.KernelStackReserve;

    public override string Message =>
        $"Image {ImageSize} + bss {BssSize} + stack {StackSize} + kernel reserve {ArenaLimits.KernelStackReserve} "
        + $"= {RequiredBytes} bytes, more than the {ArenaLimits.ArenaBytes}-byte arena.";
}

public sealed record BadMagic(byte B0, byte B1, byte B2) : C5xError
{
    public override string Message => $"Not a C5X file: magic is {B0:X2}h {B1:X2}h {B2:X2}h, expected \"C5X\".";
}

public sealed record UnsupportedVersion(byte Version) : C5xError
{
    public override string Message => $"Unsupported C5X version {Version}, expected {C5xFile.Version}.";
}

public sealed record ReservedNotZero : C5xError
{
    public override string Message => "Header reserved bytes 12-15 must be zero.";
}

public sealed record Truncated(int ExpectedBytes, int ActualBytes) : C5xError
{
    public override string Message => $"Truncated C5X file: {ActualBytes} bytes, expected {ExpectedBytes}.";
}

public sealed record TrailingData(int ExpectedBytes, int ActualBytes) : C5xError
{
    public override string Message => $"C5X file has {ActualBytes - ExpectedBytes} byte(s) after the relocation bitmap.";
}

public sealed record BitmapPaddingNotZero : C5xError
{
    public override string Message => "Relocation bitmap bits past the end of the image must be zero.";
}

public sealed class C5xException(C5xError error) : Exception(error.Message)
{
    public C5xError Error { get; } = error;
}
