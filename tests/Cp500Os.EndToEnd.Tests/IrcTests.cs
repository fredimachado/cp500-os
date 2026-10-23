using System.Net;
using System.Net.Sockets;
using System.Text;
using Cp500Os.C5fs;

namespace Cp500Os.EndToEnd.Tests;

public sealed class IrcTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("cp500-os-irc-").FullName;

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    [Fact]
    public async Task ReplayScriptCoversRegistrationUiAndQuit()
    {
        string image = CopyImage();
        byte[] demo = File.ReadAllBytes(Path.Combine(RepoPaths.Root, "programs", "irc-demo.txt"));
        Volume volume = Volume.Open(File.ReadAllBytes(image));
        volume.WriteFile("/home/irc-demo", demo);
        File.WriteAllBytes(image, volume.ToImage());

        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image, "--write-back", "--timeout", "120s",
            "--until-screen", "sh>",
            "--type", "/bin/irc -r /home/irc-demo /home/t.out fredi{ENTER}",
            "--until-screen", "online",
            "--type", "{ENTER}",
            "--until-screen", "fredi_",
            "--type", "{ENTER}",
            "--until-screen", "fredi__",
            "--type", "{ENTER}",
            "--until-screen", "Welcome",
            "--type", "{ENTER}",
            "--until-screen", "hello channel",
            "--type", "{ENTER}",
            "--until-screen", "  aa",
            "--type", "{ENTER}",
            "--until-screen", "caf",
            "--type", "/join #one{ENTER}",
            "--until-screen", "#one",
            "--type", "/join #two{ENTER}",
            "--until-screen", "#two",
            "--type", "/join #three{ENTER}",
            "--until-screen", "no free",
            "--type", "{ENTER}",
            "--until-screen", "hidden",
            "--type", "{DOWN}/win 0{ENTER}",
            "--until-screen", "act:",
            "--type", "{ENTER}",
            "--until-screen", "waves",
            "--type", "{ENTER}",
            "--type", "/quit{ENTER}",
            "--until-screen", "sh>",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, l => l.Contains("fredi__") && l.Contains("online"));
        Assert.Contains(lines, l => l.Contains("<irc.example>") && l.Contains("hello channel"));
        Assert.Contains(lines, l => l.StartsWith("  aa", StringComparison.Ordinal));
        Assert.Contains(lines, l => l.Contains("caf") && l.Contains("and"));
        Assert.Contains(lines, l => l.Contains("act:"));
        Assert.Contains(lines, l => l.Contains("* fredi__ waves") || l.Contains("*irc.example*"));
        Assert.Contains(lines, l => l.Contains("sh>"));

        string transcript = Encoding.ASCII.GetString(Volume.Open(File.ReadAllBytes(image)).ReadFile("/home/t.out"));
        Assert.Contains("NICK fredi", transcript);
        Assert.Contains("NICK fredi_", transcript);
        Assert.Contains("PONG :keepalive", transcript);
        Assert.Contains("QUIT :", transcript);
    }

    /// <summary>
    /// LEFT is the CP-500 backspace key (ESC [ D). It must rub out input, not
    /// jump through a broken CSI table and exit 68 (ASCII 'D').
    /// </summary>
    [Fact]
    public async Task LeftArrowRubsOutInputWithoutExiting()
    {
        await using LocalIrcServer server = new();
        server.Start();
        int hayesPort = FreeTcpPort();

        string image = CopyImage();
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image, "--timeout", "30s",
            "--rs232", $"hayes:{hayesPort}",
            "--until-screen", "sh>",
            "--type", $"/bin/irc carol 127.0.0.1:{server.Port} #lobby{{ENTER}}",
            "--until-screen", "welcome to #lobby",
            "--type", "xy{LEFT}{LEFT}ok{ENTER}",
            "--until-screen", "<carol> ok",
            "--type", "/quit{ENTER}",
            "--until-screen", "sh>",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.DoesNotContain(Visible(run.Stdout), l => l.Contains("exit 68", StringComparison.Ordinal));
        Assert.Contains(server.ClientLines, l => l.Contains("PRIVMSG #lobby :ok", StringComparison.Ordinal));
    }

    /// <summary>
    /// Live Hayes dial: NICK/USER over real TCP; session stays online after 001.
    /// </summary>
    [Fact]
    public async Task ModemDialRegistersOverTcp()
    {
        await using LocalIrcServer server = new();
        server.Start();
        int hayesPort = FreeTcpPort();
        using CancellationTokenSource cancel = new(TimeSpan.FromSeconds(60));

        Task<RunResult> runTask = Task.Run(async () =>
        {
            string image = CopyImage();
            return await HeadlessRunner.RunAsync(
                "--rom", Roms.Stub, "--disk0", image, "--timeout", "45s",
                "--rs232", $"hayes:{hayesPort}",
                "--until-screen", "sh>",
                "--type", $"/bin/irc fredi 127.0.0.1:{server.Port}{{ENTER}}",
                "--until-screen", "online",
                "--run", "3s",
                "--dump-screen");
        }, cancel.Token);

        await server.WaitRegisteredAsync(cancel.Token);
        RunResult run = await runTask;

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        Assert.True(server.SawClient("NICK fredi"), string.Join('\n', server.ClientLines));
        Assert.True(server.SawClient("USER fredi"), string.Join('\n', server.ClientLines));
        Assert.Contains(Visible(run.Stdout), l => l.Contains("online", StringComparison.Ordinal));
        Assert.DoesNotContain(Visible(run.Stdout), l => l.Contains("offline", StringComparison.Ordinal));
    }

    /// <summary>
    /// Dial to a port nobody listens on: the modem answers NO CARRIER and the client exits
    /// with EIO, back at the shell.
    /// </summary>
    [Fact]
    public async Task ModemDialReportsNoCarrier()
    {
        int deadPort = FreeTcpPort();
        int hayesPort = FreeTcpPort();
        string image = CopyImage();
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image, "--timeout", "30s",
            "--rs232", $"hayes:{hayesPort}",
            "--until-screen", "sh>",
            "--type", $"/bin/irc carol 127.0.0.1:{deadPort}{{ENTER}}",
            "--until-screen", "NO CARRIER",
            "--until-screen", "EIO",
            "--run", "500ms",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, l => l.Contains("NO CARRIER", StringComparison.Ordinal));
        Assert.StartsWith("sh>", lines[^1], StringComparison.Ordinal);
    }

    /// <summary>
    /// The server drops the TCP link. The modem only notices on a write, so the client
    /// shows offline after the second line it sends.
    /// </summary>
    [Fact]
    public async Task ModemHangupGoesOffline()
    {
        await using LocalIrcServer server = new();
        server.Start();
        int hayesPort = FreeTcpPort();

        string image = CopyImage();
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image, "--timeout", "30s",
            "--rs232", $"hayes:{hayesPort}",
            "--until-screen", "sh>",
            "--type", $"/bin/irc carol 127.0.0.1:{server.Port} #lobby{{ENTER}}",
            "--until-screen", "welcome to #lobby",
            "--type", "drop{ENTER}",
            "--run", "500ms",
            "--type", "one{ENTER}",
            "--run", "500ms",
            "--type", "two{ENTER}",
            "--until-screen", "offline",
            "--dump-screen");

        string client = string.Join('\n', server.ClientLines);
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout + "\nclient:\n" + client);
        Assert.True(server.SawClient("PRIVMSG #lobby :drop"), client);
        Assert.Contains(Visible(run.Stdout), l => l.Contains("offline", StringComparison.Ordinal));
    }

    /// <summary>
    /// /quit hangs the modem up, so the next /bin/irc dials again and registers with a
    /// second server.
    /// </summary>
    [Fact]
    public async Task ModemRedialsAfterQuit()
    {
        await using LocalIrcServer first = new();
        await using LocalIrcServer second = new();
        first.Start();
        second.Start();
        int hayesPort = FreeTcpPort();
        using CancellationTokenSource cancel = new(TimeSpan.FromSeconds(60));

        string image = CopyImage();
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image, "--timeout", "30s",
            "--rs232", $"hayes:{hayesPort}",
            "--until-screen", "sh>",
            "--type", $"/bin/irc carol 127.0.0.1:{first.Port}{{ENTER}}",
            "--until-screen", "Welcome to the test net",
            "--type", "/quit{ENTER}",
            "--until-screen", "sh>",
            "--type", $"/bin/irc carol 127.0.0.1:{second.Port}{{ENTER}}",
            "--until-screen", "Welcome to the test net",
            "--dump-screen");

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        await first.WaitQuitAsync(cancel.Token);
        await second.WaitRegisteredAsync(cancel.Token);
        Assert.True(first.SawClient("QUIT"), string.Join('\n', first.ClientLines));
        Assert.True(second.SawClient("NICK carol"), string.Join('\n', second.ClientLines));
        Assert.Contains(Visible(run.Stdout), l => l.Contains("online", StringComparison.Ordinal));
        Assert.DoesNotContain(Visible(run.Stdout), l => l.Contains("offline", StringComparison.Ordinal));
    }

    /// <summary>
    /// Live Hayes session: autojoin and /join, read and send channel messages,
    /// then the other slash commands, checked on screen and on the wire.
    /// </summary>
    [Fact]
    public async Task ModemDialChatsOverTcp()
    {
        await using LocalIrcServer server = new();
        server.Start();
        int hayesPort = FreeTcpPort();

        string image = CopyImage();
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image, "--timeout", "30s",
            "--rs232", $"hayes:{hayesPort}",
            "--until-screen", "sh>",
            "--type", $"/bin/irc carol 127.0.0.1:{server.Port} #lobby{{ENTER}}",
            "--until-screen", "welcome to #lobby",
            "--until-screen", "[2] #lobby",
            "--type", "hi lobby{ENTER}",
            "--until-screen", "bob heard you",
            "--type", "/join #room{ENTER}",
            "--until-screen", "welcome to #room",
            "--until-screen", "[3] #room",
            "--type", "hello room{ENTER}",
            "--until-screen", "<carol> hello room",
            "--until-screen", "bob heard you",
            "--type", "/me waves{ENTER}",
            "--until-screen", "* carol waves",
            "--type", "/msg bob secret{ENTER}",
            "--run", "500ms",
            "--type", "/nick cara{ENTER}",
            "--until-screen", "#room   cara",
            "--type", "/names{ENTER}",
            "--run", "500ms",
            "--type", "/whois bob{ENTER}",
            "--run", "500ms",
            "--type", "/quote TIME{ENTER}",
            "--run", "500ms",
            "--type", "/part{ENTER}",
            "--until-screen", "[1] -",
            "--type", "/quit bye{ENTER}",
            "--until-screen", "sh>",
            "--dump-screen");

        string client = string.Join('\n', server.ClientLines);
        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout + "\nclient:\n" + client);
        string[] expected =
        [
            "NICK carol", "USER carol 0 * :CP-500", "JOIN #lobby", "PRIVMSG #lobby :hi lobby",
            "JOIN #room", "PRIVMSG #room :hello room", "PRIVMSG #room :\u0001ACTION waves\u0001",
            "PRIVMSG bob :secret", "NICK cara", "NAMES #room", "WHOIS bob", "TIME", "PART #room",
            "QUIT :bye",
        ];
        Assert.Equal(expected, server.ClientLines);
    }

    private static int FreeTcpPort()
    {
        using TcpListener probe = new(IPAddress.Loopback, 0);
        probe.Start();
        return ((IPEndPoint)probe.LocalEndpoint).Port;
    }

    private string CopyImage()
    {
        string path = Path.Combine(_directory, "disk.dsk");
        File.Copy(Product(), path);
        return path;
    }

    private static string Product() => Path.Combine(RepoPaths.Root, "build", "cp500-os.dsk");

    private static string[] Visible(string stdout) =>
    [
        .. stdout.Split('\n')
            .Select(line => line.Replace("\U0001FB2D", "").TrimEnd(' ', '\r'))
            .Where(line => line.Length > 0 && !(line.Length > 5 && line[4] == ':' &&
                int.TryParse(line.AsSpan(0, 4), System.Globalization.NumberStyles.HexNumber, null, out _))),
    ];
}
