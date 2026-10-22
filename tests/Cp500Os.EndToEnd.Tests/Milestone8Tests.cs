using System.Net;
using System.Net.Sockets;
using Cp500Os.Tests;

namespace Cp500Os.EndToEnd.Tests;

public sealed class Milestone8Tests
{
    [Fact]
    public async Task SocketWithoutABoardIsEnodev()
    {
        RunResult run = await RunFixtureAsync("/lib/nettest.c5x", "exit 18");
        AssertExit(run, 18);
    }

    [Fact]
    public async Task BadSocketTypeIsEinval()
    {
        RunResult run = await RunFixtureAsync("/lib/nettest.c5x t", "exit 5");
        AssertExit(run, 5);
    }

    [Fact]
    public async Task ReservedSocketCallIsEinval()
    {
        RunResult run = await RunFixtureAsync("/lib/nettest.c5x b", "exit 5");
        AssertExit(run, 5);
    }

    [Fact]
    public async Task TelnetEchoesAndReportsClosed()
    {
        W5100Board.Require();
        using var listen = new TcpListener(IPAddress.Loopback, 0);
        listen.Start();
        int port = ((IPEndPoint)listen.LocalEndpoint).Port;
        var args = new List<string>
        {
            "--rom", Roms.Stub,
            "--disk0", Product(),
            "--w5100",
            "--until-screen", "sh>",
            "--timeout", "20s",
            "--type", $"/bin/telnet 127.0.0.1 {port}{{ENTER}}",
            "--until-screen", "connected",
            "--type", "Hi{ENTER}",
            "--until-screen", "Yo",
            "--until-screen", "closed",
            "--dump-screen",
        };
        Task<RunResult> run = HeadlessRunner.RunAsync([.. args]);
        using TcpClient peer = await listen.AcceptTcpClientAsync(TestContext.Current.CancellationToken);
        using NetworkStream stream = peer.GetStream();
        var got = new byte[4];
        int n = 0;
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (n < 4 && DateTime.UtcNow < deadline)
        {
            if (peer.Available > 0)
                n += await stream.ReadAsync(got.AsMemory(n, 4 - n), TestContext.Current.CancellationToken);
            else
                await Task.Delay(20, TestContext.Current.CancellationToken);
        }

        Assert.Equal(4, n);
        Assert.Equal("Hi\r\n"u8.ToArray(), got.AsSpan(0, 4).ToArray());
        await stream.WriteAsync("Yo"u8.ToArray(), TestContext.Current.CancellationToken);
        peer.Client.Shutdown(SocketShutdown.Send);
        RunResult finished = await run;
        Assert.True(finished.ExitCode == 0, finished.Stderr + finished.Stdout);
        Assert.Contains("connected", Visible(finished.Stdout));
        Assert.Contains(Visible(finished.Stdout), line => line.Contains("Hi", StringComparison.Ordinal));
        Assert.Contains(Visible(finished.Stdout), line => line.Contains("Yo", StringComparison.Ordinal));
        Assert.Contains(Visible(finished.Stdout), line => line.Contains("closed", StringComparison.Ordinal));
    }

    [Fact]
    public async Task GetPrintsOkForHttp200()
    {
        W5100Board.Require();
        using var listen = new TcpListener(IPAddress.Loopback, 0);
        listen.Start();
        int port = ((IPEndPoint)listen.LocalEndpoint).Port;
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Task serve = ServeHttpOnceAsync(listen, release.Task);
        RunResult run;
        try
        {
            run = await RunNetworkAsync(
                $"/bin/get http://127.0.0.1:{port}/ok",
                "GET OK");
        }
        finally
        {
            release.TrySetResult();
        }

        await serve;
        Assert.Contains("GET OK", Visible(run.Stdout));
    }

    [Fact]
    public async Task TimesyncSetsClockFromPort37()
    {
        W5100Board.Require();
        RunResult run = await RunNetworkAsync(
            "/bin/timesync{ENTER}/bin/date",
            "TIME OK",
            "2026-01-01 00:00:00");
        Assert.Contains("TIME OK", Visible(run.Stdout));
        Assert.Contains("2026-01-01 00:00:00", Visible(run.Stdout));
    }

    private static async Task ServeHttpOnceAsync(TcpListener listen, Task release)
    {
        using TcpClient client = await listen.AcceptTcpClientAsync(TestContext.Current.CancellationToken);
        using NetworkStream stream = client.GetStream();
        byte[] response = "HTTP/1.0 200 OK\r\n\r\nOK"u8.ToArray();
        await stream.WriteAsync(response, TestContext.Current.CancellationToken);
        client.Client.Shutdown(SocketShutdown.Send);
        await release.WaitAsync(TestContext.Current.CancellationToken);
        var buffer = new byte[256];
        while (client.Available > 0 && await stream.ReadAsync(buffer, TestContext.Current.CancellationToken) > 0)
        {
        }
    }

    private static async Task<RunResult> RunFixtureAsync(string command, string until)
    {
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", Product(),
            "--until-screen", "sh>", "--timeout", "20s",
            "--type", command + "{ENTER}",
            "--until-screen", until,
            "--dump-screen");
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        return run;
    }

    private static async Task<RunResult> RunNetworkAsync(string command, params string[] until)
    {
        var args = new List<string>
        {
            "--rom", Roms.Stub,
            "--disk0", Product(),
            "--w5100",
            "--until-screen", "sh>",
            "--timeout", "20s",
            "--type", command + "{ENTER}",
        };
        foreach (string text in until)
        {
            args.Add("--until-screen");
            args.Add(text);
        }

        args.Add("--dump-screen");
        RunResult run = await HeadlessRunner.RunAsync(args.ToArray());
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        return run;
    }

    private static void AssertExit(RunResult run, int code)
    {
        Assert.Contains(Visible(run.Stdout), line => line == $"exit {code}");
    }

    private static string Product() => Path.Combine(RepoPaths.Root, "build", "cp500-os.dsk");

    private static string[] Visible(string stdout) =>
    [
        .. stdout.Split('\n')
            .Select(line => line.Replace("\U0001FB2D", "").TrimEnd(' ', '\r'))
            .Where(line => line.Length > 0 && !IsDump(line)),
    ];

    private static bool IsDump(string line) =>
        line.Length > 5 && line[4] == ':' &&
        int.TryParse(line.AsSpan(0, 4), System.Globalization.NumberStyles.HexNumber, null, out _);
}

internal static class W5100Board
{
    private static bool? _accepted;

    public static void Require()
    {
        if (_accepted ??= Probe())
            return;

        Assert.Skip("pinned heh8080 has no W5100; network path was not run");
    }

    private static bool Probe()
    {
        string exe = Path.Combine(AppContext.BaseDirectory, OperatingSystem.IsWindows() ? "heh8080-cp500.exe" : "heh8080-cp500");
        var startInfo = new System.Diagnostics.ProcessStartInfo(exe)
        {
            RedirectStandardOutput = true,
            UseShellExecute = false,
            ArgumentList = { "--help" },
        };
        using var process = System.Diagnostics.Process.Start(startInfo) ?? throw new InvalidOperationException("Could not start runner.");
        string text = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        return text.Contains("--w5100", StringComparison.Ordinal);
    }
}
