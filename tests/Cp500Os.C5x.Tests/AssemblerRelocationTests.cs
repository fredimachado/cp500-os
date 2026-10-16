using Cp500Os.MkReloc.Cli;

namespace Cp500Os.C5x.Tests;

/// <summary>mkreloc on tests/fixtures/z80/reloc-sample.asm as linked by sjasmplus at 0000h, 0100h and 6200h.</summary>
public sealed class AssemblerRelocationTests : IDisposable
{
    private readonly DirectoryInfo _directory = Directory.CreateTempSubdirectory("mkreloc-asm-");

    public void Dispose() => _directory.Delete(recursive: true);

    [Fact]
    public void RelocatingThe0000hLinkToPage62hReproducesThe6200hLink()
    {
        var program = BuildWithMkReloc();

        Assert.Equal(Z80Fixtures.Read("reloc-sample-6200.bin"), program.RelocateTo(0x62));
    }

    [Fact]
    public void MarksExactlyTheAbsoluteAddressHighBytes()
    {
        var program = BuildWithMkReloc();

        // From build/z80/reloc-sample-0000.lst: ld sp, ld hl, call, ld a,(nn), ld (nn),a, jp z,
        // ld ix, and the three dw table entries. The jr/djnz displacements and ld bc,0100h are not addresses.
        Assert.Equal([0x02, 0x05, 0x0F, 0x19, 0x1D, 0x22, 0x2A, 0x30, 0x32, 0x34], program.Relocations.MarkedOffsets());
    }

    private C5xProgram BuildWithMkReloc()
    {
        string output = Path.Combine(_directory.FullName, "reloc-sample.c5x");
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();

        int exitCode = MkRelocCommand.Run(
            [Z80Fixtures.PathOf("reloc-sample-0000.bin"), Z80Fixtures.PathOf("reloc-sample-0100.bin"), "-o", output],
            stdout,
            stderr);

        Assert.True(exitCode == 0, stderr.ToString());
        return C5xFile.Parse(File.ReadAllBytes(output));
    }
}
