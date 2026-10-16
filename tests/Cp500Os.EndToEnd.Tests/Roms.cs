namespace Cp500Os.EndToEnd.Tests;

internal static class Roms
{
    public const string RealRomVariable = "CP500_ROM";

    public static string Stub => RepoPaths.Z80Output("stub.rom");

    /// <summary>
    /// The copyrighted CP-500 ROM dump (CRC32 c2fc1b92) from CP500_ROM or roms/cp500.rom. It is never
    /// committed, so tests that need it skip when it is absent.
    /// </summary>
    public static string RequireReal()
    {
        string path = Environment.GetEnvironmentVariable(RealRomVariable) is { Length: > 0 } fromEnvironment
            ? fromEnvironment
            : Path.Combine(RepoPaths.Root, "roms", "cp500.rom");
        if (!File.Exists(path))
            Assert.Skip($"The CP-500 ROM is not at {path}. Set {RealRomVariable} or copy the dump to roms/cp500.rom.");

        return path;
    }
}
