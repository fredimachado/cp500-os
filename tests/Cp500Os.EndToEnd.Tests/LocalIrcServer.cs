using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Cp500Os.EndToEnd.Tests;

/// <summary>
/// Minimal IRC server over real TCP for Hayes modem E2E tests. It welcomes the
/// client after NICK and USER, echoes JOIN/PART/NICK the way a real server does,
/// and has "bob" greet each joined channel and answer every channel message.
/// </summary>
internal sealed class LocalIrcServer : IAsyncDisposable
{
    private readonly TcpListener _listener = new(IPAddress.Loopback, 0);
    private readonly CancellationTokenSource _stop = new();
    private readonly ConcurrentQueue<string> _fromClient = new();
    private readonly TaskCompletionSource _registered = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly TaskCompletionSource _quit = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private Task? _run;

    public int Port { get; private set; }
    public IReadOnlyCollection<string> ClientLines => _fromClient.ToArray();

    public void Start()
    {
        _listener.Start();
        Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
        _run = RunAsync(_stop.Token);
    }

    public Task WaitRegisteredAsync(CancellationToken cancel) =>
        _registered.Task.WaitAsync(cancel);

    public Task WaitQuitAsync(CancellationToken cancel) =>
        _quit.Task.WaitAsync(cancel);

    public bool SawClient(string prefix) =>
        _fromClient.Any(l => l.StartsWith(prefix, StringComparison.Ordinal));

    private async Task RunAsync(CancellationToken cancel)
    {
        using TcpClient client = await _listener.AcceptTcpClientAsync(cancel);
        client.NoDelay = true;
        await using NetworkStream stream = client.GetStream();

        var line = new StringBuilder();
        var buf = new byte[256];
        string nick = "";
        bool gotUser = false;

        while (!cancel.IsCancellationRequested)
        {
            int n = await stream.ReadAsync(buf.AsMemory(0, buf.Length), cancel);
            if (n <= 0)
                break;

            for (int i = 0; i < n; i++)
            {
                char ch = (char)buf[i];
                if (ch != '\r' && ch != '\n')
                {
                    line.Append(ch);
                    continue;
                }

                string text = line.ToString();
                line.Clear();
                if (text.Length == 0)
                    continue;

                _fromClient.Enqueue(text);
                string[] words = text.Split(' ');
                string arg = words.Length > 1 ? words[1] : "";
                switch (words[0])
                {
                    case "NICK":
                        if (_registered.Task.IsCompleted)
                            await SendAsync(stream, $":{nick}!u@h NICK :{arg}", cancel);
                        nick = arg;
                        break;
                    case "USER":
                        gotUser = true;
                        break;
                    case "PING":
                        await SendAsync(stream, $"PONG :{arg.TrimStart(':')}", cancel);
                        break;
                    case "JOIN":
                        await SendAsync(stream, $":{nick}!u@h JOIN :{arg}", cancel);
                        await SendAsync(stream, $":irc.test 332 {nick} {arg} :Topic of {arg}", cancel);
                        await SendAsync(stream, $":irc.test 353 {nick} = {arg} :{nick} bob alice", cancel);
                        await SendAsync(stream, $":irc.test 366 {nick} {arg} :End of NAMES", cancel);
                        await SendAsync(stream, $":bob!b@h PRIVMSG {arg} :hi {nick}, welcome to {arg}", cancel);
                        break;
                    case "PART":
                        await SendAsync(stream, $":{nick}!u@h PART {arg}", cancel);
                        break;
                    case "PRIVMSG" when text.EndsWith(" :drop", StringComparison.Ordinal):
                        // The server pulls the link without a reply; the client finds out on its next writes.
                        return;
                    case "PRIVMSG" when arg.StartsWith('#'):
                        await SendAsync(stream, $":bob!b@h PRIVMSG {arg} :bob heard you", cancel);
                        break;
                    case "QUIT":
                        _quit.TrySetResult();
                        return;
                }

                if (nick.Length > 0 && gotUser && !_registered.Task.IsCompleted)
                {
                    _registered.TrySetResult();
                    await SendAsync(stream, $":irc.test 001 {nick} :Welcome to the test net", cancel);
                }
            }
        }
    }

    private static Task SendAsync(NetworkStream stream, string line, CancellationToken cancel) =>
        stream.WriteAsync(Encoding.ASCII.GetBytes(line + "\r\n"), cancel).AsTask();

    public async ValueTask DisposeAsync()
    {
        await _stop.CancelAsync();
        _listener.Stop();
        if (_run is not null)
        {
            try
            {
                await _run.WaitAsync(TimeSpan.FromSeconds(2));
            }
            catch (Exception ex) when (ex is TimeoutException or OperationCanceledException or IOException or SocketException)
            {
                // Guest already gone or accept aborted.
            }
        }

        _stop.Dispose();
        _quit.TrySetCanceled();
        _registered.TrySetCanceled();
    }
}
