namespace Cp500Os.Tests;

/// <summary>Locates repository files from test binaries, which build under build/artifacts.</summary>
internal static class RepoPaths
{
    public static string Root { get; } = FindRoot();

    /// <summary>A binary assembled by eng/Z80.targets into build/z80.</summary>
    public static string Z80Output(string fileName) => Path.Combine(Root, "build", "z80", fileName);

    public static byte[] ReadZ80Output(string fileName) => File.ReadAllBytes(Z80Output(fileName));

    private static string FindRoot()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            if (File.Exists(Path.Combine(directory.FullName, "global.json")))
                return directory.FullName;
        }

        throw new InvalidOperationException($"No global.json above {AppContext.BaseDirectory}.");
    }
}
