namespace Cp500Os.C5x.Tests;

/// <summary>Binaries that tests/fixtures/z80/Cp500Os.Fixtures.Z80.proj assembles into build/z80.</summary>
internal static class Z80Fixtures
{
    public static string PathOf(string fileName) => Path.Combine(FindRepoRoot(), "build", "z80", fileName);

    public static byte[] Read(string fileName) => File.ReadAllBytes(PathOf(fileName));

    private static string FindRepoRoot()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            if (File.Exists(Path.Combine(directory.FullName, "global.json")))
                return directory.FullName;
        }

        throw new InvalidOperationException($"No global.json above {AppContext.BaseDirectory}.");
    }
}
