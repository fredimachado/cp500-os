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
            "--type", "/join #one{ENTER}/join #two{ENTER}/join #three{ENTER}",
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

        string transcript = System.Text.Encoding.ASCII.GetString(Volume.Open(File.ReadAllBytes(image)).ReadFile("/home/t.out"));
        Assert.Contains("NICK fredi", transcript);
        Assert.Contains("NICK fredi_", transcript);
        Assert.Contains("PONG :keepalive", transcript);
        Assert.Contains("QUIT :", transcript);
    }

    [Fact]
    public async Task ModemDialRegistersAndQuits()
    {
        SerialBoard.Require();

        using TcpListener listener = new(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        using CancellationTokenSource dialCancel = new(TimeSpan.FromSeconds(25));
        Task bridge = AcceptModemAsync(listener, dialCancel.Token);

        string image = CopyImage();
        RunResult run = await HeadlessRunner.RunAsync(
            "--rom", Roms.Stub, "--disk0", image, "--write-back", "--timeout", "120s",
            "--until-screen", "sh>",
            "--type", $"/bin/irc fredi 127.0.0.1:{port}{{ENTER}}",
            "--until-screen", "online",
            "--type", "/quit{ENTER}",
            "--until-screen", "sh>",
            "--dump-screen");

        await bridge;

        Assert.True(run.ExitCode == 0, run.Stderr + run.Stdout);
        string[] lines = Visible(run.Stdout);
        Assert.Contains(lines, l => l.Contains("fredi") && l.Contains("online"));
    }

    private static async Task AcceptModemAsync(TcpListener listener, CancellationToken cancel)
    {
        using TcpClient client = await listener.AcceptTcpClientAsync(cancel);
        await using NetworkStream stream = client.GetStream();
        StringBuilder cmd = new();
        bool online = false;
        byte[] buf = new byte[256];
        while (!cancel.IsCancellationRequested)
        {
            if (!stream.DataAvailable)
            {
                await Task.Delay(10, cancel);
                continue;
            }

            int n = await stream.ReadAsync(buf, cancel);
            if (n <= 0)
                break;

            for (int i = 0; i < n; i++)
            {
                char ch = (char)buf[i];
                if (ch == '\r')
                {
                    string line = cmd.ToString();
                    cmd.Clear();
                    if (line == "ATE0V1")
                        await WriteAsciiAsync(stream, "\r\nOK\r\n", cancel);
                    else if (line.StartsWith("ATDT", StringComparison.Ordinal))
                    {
                        await WriteAsciiAsync(stream, "\r\nCONNECT 9600\r\n", cancel);
                        online = true;
                    }
                    else if (online)
                    {
                        if (line.StartsWith("NICK ", StringComparison.Ordinal))
                            await WriteAsciiAsync(stream, ":irc.test 001 fredi :Welcome\r\n", cancel);
                        else if (line.StartsWith("USER ", StringComparison.Ordinal))
                            await WriteAsciiAsync(stream, ":irc.test 002 fredi :logged in\r\n", cancel);
                        else if (line.StartsWith("QUIT", StringComparison.Ordinal))
                            return;
                    }
                }
                else if (ch != '\n')
                    cmd.Append(ch);
            }
        }
    }

    private static async Task WriteAsciiAsync(NetworkStream stream, string text, CancellationToken cancel) =>
        await stream.WriteAsync(Encoding.ASCII.GetBytes(text), cancel);

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
            .Select(line => line.Replace("\u2588", "").TrimEnd(' ', '\r'))
            .Where(line => line.Length > 0 && !(line.Length > 5 && line[4] == ':' &&
                int.TryParse(line.AsSpan(0, 4), System.Globalization.NumberStyles.HexNumber, null, out _))),
    ];
}
