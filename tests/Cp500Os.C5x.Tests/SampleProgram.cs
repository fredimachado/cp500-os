namespace Cp500Os.C5x.Tests;

/// <summary>A 12-byte hand-linked program at three origins.</summary>
internal static class SampleProgram
{
    // 0000  C3 06 00   jp   start        absolute
    // 0003  18 01      jr   +1           relative, not relocated
    // 0005  00         nop
    // 0006  21 0A 00   start: ld hl,table
    // 0009  C9         ret
    // 000A  06 00      table: dw start
    public static readonly byte[] At0000 = [0xC3, 0x06, 0x00, 0x18, 0x01, 0x00, 0x21, 0x0A, 0x00, 0xC9, 0x06, 0x00];

    public static readonly byte[] At0100 = [0xC3, 0x06, 0x01, 0x18, 0x01, 0x00, 0x21, 0x0A, 0x01, 0xC9, 0x06, 0x01];

    public static readonly byte[] At6200 = [0xC3, 0x06, 0x62, 0x18, 0x01, 0x00, 0x21, 0x0A, 0x62, 0xC9, 0x06, 0x62];

    public static readonly int[] RelocatedOffsets = [2, 8, 11];

    public static readonly byte[] Bitmap = [0x04, 0x09];
}
