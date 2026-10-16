using System.Diagnostics;
using System.Globalization;

namespace Cp500Os.EndToEnd.Tests;

internal sealed record RunResult(int ExitCode, string Stdout, string Stderr)
{
    /// <summary>Bytes from the runner's --dump-memory lines ("4300: 3E 20 ...").</summary>
    public byte[] DumpedMemory() =>
    [
        .. Stdout.Split('\n')
            .Where(line => line.Length > 5 && line[4] == ':' && IsHex(line.AsSpan(0, 4)))
            .SelectMany(line => line[5..].Split(' ', StringSplitOptions.RemoveEmptyEntries))
            .Select(hex => byte.Parse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture)),
    ];

    private static bool IsHex(ReadOnlySpan<char> text) => int.TryParse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out _);
}

/// <summary>Runs heh8080's headless CP-500 runner as a separate process, the way CI and developers do.</summary>
internal static class HeadlessRunner
{
    private static readonly TimeSpan WallClockLimit = TimeSpan.FromMinutes(2);

    private static string Executable { get; } =
        Path.Combine(AppContext.BaseDirectory, OperatingSystem.IsWindows() ? "heh8080-cp500.exe" : "heh8080-cp500");

    public static async Task<RunResult> RunAsync(params string[] arguments)
    {
        var startInfo = new ProcessStartInfo(Executable)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        foreach (string argument in arguments)
            startInfo.ArgumentList.Add(argument);

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException($"Could not start {Executable}.");
        using var timeout = new CancellationTokenSource(WallClockLimit);
        Task<string> stdout = process.StandardOutput.ReadToEndAsync(timeout.Token);
        Task<string> stderr = process.StandardError.ReadToEndAsync(timeout.Token);
        await process.WaitForExitAsync(timeout.Token);
        return new RunResult(process.ExitCode, await stdout, await stderr);
    }
}
