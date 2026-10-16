using Cp500Os.MkReloc.Cli;

namespace Cp500Os.C5x.Tests;

public sealed class MkRelocCommandTests : IDisposable
{
    private readonly DirectoryInfo _directory = Directory.CreateTempSubdirectory("mkreloc-tests-");
    private readonly StringWriter _output = new();
    private readonly StringWriter _error = new();

    public void Dispose()
    {
        _directory.Delete(recursive: true);
        _output.Dispose();
        _error.Dispose();
    }

    [Fact]
    public void WritesAC5xFileWithDefaultSizes()
    {
        int exitCode = Run(WriteFile("a.bin", SampleProgram.At0000), WriteFile("b.bin", SampleProgram.At0100), "-o", PathOf("p.c5x"));

        Assert.Equal(0, exitCode);
        Assert.Equal("", _error.ToString());
        var program = C5xFile.Parse(File.ReadAllBytes(PathOf("p.c5x")));
        Assert.Equal(new C5xHeader(12, bssSize: 0, stackSize: 256, entryOffset: 0), program.Header);
        Assert.Equal(SampleProgram.Bitmap, program.Relocations.Bytes.ToArray());
    }

    [Fact]
    public void AcceptsDecimalAndHexSizes()
    {
        int exitCode = Run(
            WriteFile("a.bin", SampleProgram.At0000), WriteFile("b.bin", SampleProgram.At0100),
            "--output", PathOf("p.c5x"), "--bss", "0x1F0", "--stack", "512", "--entry", "0X6");

        Assert.Equal(0, exitCode);
        Assert.Equal(new C5xHeader(12, 0x1F0, 512, 6), C5xFile.Parse(File.ReadAllBytes(PathOf("p.c5x"))).Header);
    }

    [Fact]
    public void InfoPrintsTheHeader()
    {
        Run(WriteFile("a.bin", SampleProgram.At0000), WriteFile("b.bin", SampleProgram.At0100), "-o", PathOf("p.c5x"), "--bss", "100", "--entry", "6");

        int exitCode = Run("--info", PathOf("p.c5x"));

        Assert.Equal(0, exitCode);
        Assert.Equal(
            """
            version      1
            image        12 bytes
            bss          100 bytes
            stack        256 bytes (+192 kernel reserve)
            entry        0006h
            relocations  3
            memory       560 bytes, 3 pages

            """.ReplaceLineEndings(),
            _output.ToString());
    }

    [Fact]
    public void ReportsNonRelocatableDifferencesAndWritesNothing()
    {
        byte[] bad = [.. SampleProgram.At0100];
        bad[4] = 0x03;

        int exitCode = Run(WriteFile("a.bin", SampleProgram.At0000), WriteFile("b.bin", bad), "-o", PathOf("p.c5x"));

        Assert.Equal(1, exitCode);
        Assert.Equal(
            "mkreloc: 1 byte(s) differ between the links by something other than +1: 0004h (01h -> 03h)." + Environment.NewLine,
            _error.ToString());
        Assert.False(File.Exists(PathOf("p.c5x")));
    }

    [Fact]
    public void ReportsAnEntryOutsideTheImage()
    {
        int exitCode = Run(WriteFile("a.bin", SampleProgram.At0000), WriteFile("b.bin", SampleProgram.At0100), "-o", PathOf("p.c5x"), "--entry", "0x0C");

        Assert.Equal(1, exitCode);
        Assert.Contains("Entry offset 000Ch is outside the 12-byte image.", _error.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void InfoReportsAFileThatIsNotC5x()
    {
        int exitCode = Run("--info", WriteFile("x.c5x", "C5Y\u0001"u8.ToArray()));

        Assert.Equal(1, exitCode);
        Assert.Contains("Truncated C5X file: 4 bytes, expected 16.", _error.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void RejectsAMissingOutput()
    {
        int exitCode = Run(WriteFile("a.bin", SampleProgram.At0000), WriteFile("b.bin", SampleProgram.At0100));

        Assert.NotEqual(0, exitCode);
        Assert.Contains("Expected <link0000.bin> <link0100.bin> -o <out.c5x>, or --info <file.c5x>.", _error.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void RejectsAnInvalidNumber()
    {
        int exitCode = Run(WriteFile("a.bin", SampleProgram.At0000), WriteFile("b.bin", SampleProgram.At0100), "-o", PathOf("p.c5x"), "--stack", "70000");

        Assert.NotEqual(0, exitCode);
        Assert.Contains("'70000' is not a number from 0 to 65535 (decimal or 0x hex).", _error.ToString(), StringComparison.Ordinal);
    }

    private int Run(params string[] args) => MkRelocCommand.Run(args, _output, _error);

    private string PathOf(string name) => Path.Combine(_directory.FullName, name);

    private string WriteFile(string name, byte[] contents)
    {
        File.WriteAllBytes(PathOf(name), contents);
        return PathOf(name);
    }
}
