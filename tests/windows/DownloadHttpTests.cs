using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using TokMac;

internal static class DownloadHttpTests
{
    internal static async Task Run()
    {
        await CrossHostRedirectDoesNotLeakCookies();
        await RelativeRedirectRechecksPathCookies();
        await RejectsUnsafeRedirects();
        await RedirectLoopIsBounded();
        await RealHttpTransportDoesNotForwardCookies();
        RejectsPartialVideoResponses();
        await StalledBodyFailsWithoutCommitting();
        await UserCancellationRemainsCancellation();
        await CompleteBodyCopiesAndReportsProgress();
        Console.WriteLine("9 HTTP download regression checks passed.");
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    private static void RejectsPartialVideoResponses()
    {
        foreach (var status in new[] { HttpStatusCode.PartialContent, HttpStatusCode.OK })
        {
            using var response = new HttpResponseMessage(status) { Content = new ByteArrayContent(new byte[8]) };
            response.Content.Headers.ContentType = new("video/mp4");
            response.Content.Headers.ContentRange = new(0, 7, 1000);
            try { DownloadHttpClient.ValidateVideoResponse(response); }
            catch (IOException) { continue; }
            throw new Exception("An incomplete video response was accepted");
        }
    }

    private sealed class StallingStream : MemoryStream
    {
        internal StallingStream() : base(new byte[] { 1, 2, 3 }) { }

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            if (Position < Length) return await base.ReadAsync(buffer, cancellationToken);
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return 0;
        }
    }

    private static async Task StalledBodyFailsWithoutCommitting()
    {
        using var source = new StallingStream();
        using var destination = new MemoryStream();
        using var safety = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        try
        {
            await DownloadHttpClient.CopyBodyAsync(source, destination, 8, _ => { }, TimeSpan.FromMilliseconds(100), safety.Token);
        }
        catch (TimeoutException)
        {
            Check(destination.Length == 3, "Timeout must occur after the first bytes are copied");
            return;
        }
        throw new Exception("The stalled read was allowed to complete");
    }

    private static async Task UserCancellationRemainsCancellation()
    {
        using var source = new StallingStream();
        using var destination = new MemoryStream();
        using var userCancel = new CancellationTokenSource();
        try
        {
            await DownloadHttpClient.CopyBodyAsync(source, destination, 8, _ => userCancel.Cancel(), TimeSpan.FromSeconds(2), userCancel.Token);
        }
        catch (OperationCanceledException) { return; }
        throw new Exception("The user cancellation was not propagated");
    }

    private static async Task CompleteBodyCopiesAndReportsProgress()
    {
        byte[] payload = new byte[100000];
        payload[^1] = 37;
        using var source = new MemoryStream(payload);
        using var destination = new MemoryStream();
        long progress = 0;
        await DownloadHttpClient.CopyBodyAsync(source, destination, payload.Length, written => progress = written,
            TimeSpan.FromSeconds(2), CancellationToken.None);
        Check(progress == payload.Length && destination.ToArray().AsSpan().SequenceEqual(payload), "Complete transfers must keep all bytes and report progress");
    }

    private sealed class Transport : HttpMessageHandler
    {
        internal readonly List<(Uri Uri, string Cookie)> Requests = new();
        internal required Func<Uri, HttpResponseMessage> Respond { get; init; }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add((request.RequestUri!, request.Headers.TryGetValues("Cookie", out var values) ? string.Join("; ", values) : ""));
            return Task.FromResult(Respond(request.RequestUri!));
        }
    }

    private static HttpResponseMessage Redirect(string target)
    {
        var response = new HttpResponseMessage(HttpStatusCode.Found);
        response.Headers.Location = new Uri(target, UriKind.RelativeOrAbsolute);
        return response;
    }

    private static async Task CrossHostRedirectDoesNotLeakCookies()
    {
        var transport = new Transport { Respond = url => url.Host == "first.example" ? Redirect("https://other.example/video") : new(HttpStatusCode.OK) };
        using var client = new DownloadHttpClient(transport);
        using var response = await client.GetAsync(new Uri("https://first.example/start"), "TokMacTest",
            url => Task.FromResult<string?>(url.Host == "first.example" ? "sessionid=PRIVATE" : "cdnid=OTHER"), CancellationToken.None);
        Check(transport.Requests.Count == 2, "Cross-host redirect must be followed");
        Check(transport.Requests[0].Cookie == "sessionid=PRIVATE", "Initial request must retain its own cookies");
        Check(transport.Requests[1].Cookie == "cdnid=OTHER", "Redirect must use only the target host's cookies");
    }

    private static async Task RelativeRedirectRechecksPathCookies()
    {
        var transport = new Transport { Respond = url => url.AbsolutePath == "/private/start" ? Redirect("/public/video") : new(HttpStatusCode.OK) };
        using var client = new DownloadHttpClient(transport);
        using var response = await client.GetAsync(new Uri("https://cdn.example/private/start"), "TokMacTest",
            url => Task.FromResult<string?>(url.AbsolutePath.StartsWith("/private/") ? "private=VALUE" : null), CancellationToken.None);
        Check(transport.Requests[1].Uri.AbsoluteUri == "https://cdn.example/public/video", "Relative redirect resolution failed");
        Check(transport.Requests[1].Cookie == "", "Path-limited cookies must be rechecked for relative redirects");
    }

    private static async Task RejectsUnsafeRedirects()
    {
        foreach (var target in new[] { "http://cdn.example/video", "file:///tmp/video", "https://user:pass@cdn.example/video" })
        {
            var transport = new Transport { Respond = _ => Redirect(target) };
            using var client = new DownloadHttpClient(transport);
            try
            {
                using var response = await client.GetAsync(new Uri("https://cdn.example/start"), "TokMacTest", _ => Task.FromResult<string?>(null), CancellationToken.None);
                throw new Exception("Unsafe redirect was accepted: " + target);
            }
            catch (IOException) { }
            Check(transport.Requests.Count == 1, "Unsafe target must never receive a request");
        }
    }

    private static async Task RedirectLoopIsBounded()
    {
        var transport = new Transport { Respond = _ => Redirect("/loop") };
        using var client = new DownloadHttpClient(transport);
        try
        {
            using var response = await client.GetAsync(new Uri("https://cdn.example/loop"), "TokMacTest", _ => Task.FromResult<string?>(null), CancellationToken.None);
            throw new Exception("Infinite redirect loop was accepted");
        }
        catch (IOException) { }
        Check(transport.Requests.Count == 11, "Redirect count must be bounded");
    }

    private static async Task<string> Serve(TcpListener listener, string response, CancellationToken token)
    {
        using var connection = await listener.AcceptTcpClientAsync(token);
        await using var stream = connection.GetStream();
        using var reader = new StreamReader(stream, Encoding.ASCII, leaveOpen: true);
        string cookie = "";
        string? line;
        while (!string.IsNullOrEmpty(line = await reader.ReadLineAsync(token)))
            if (line.StartsWith("Cookie:", StringComparison.OrdinalIgnoreCase)) cookie = line;
        await stream.WriteAsync(Encoding.ASCII.GetBytes(response), token);
        return cookie;
    }

    private static async Task RealHttpTransportDoesNotForwardCookies()
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        var first = new TcpListener(IPAddress.Loopback, 0);
        var second = new TcpListener(IPAddress.Loopback, 0);
        first.Start(); second.Start();
        try
        {
            int firstPort = ((IPEndPoint)first.LocalEndpoint).Port;
            int secondPort = ((IPEndPoint)second.LocalEndpoint).Port;
            var initial = Serve(first, $"HTTP/1.1 302 Found\r\nLocation: http://localhost:{secondPort}/video\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", timeout.Token);
            var redirected = Serve(second, "HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK", timeout.Token);
            using var client = new DownloadHttpClient(new HttpClientHandler { UseProxy = false });
            using var response = await client.GetAsync(new Uri($"http://127.0.0.1:{firstPort}/start"), "TokMacTest",
                url => Task.FromResult<string?>(url.Host == "127.0.0.1" ? "sessionid=FAKE_LOCAL_TEST" : null), timeout.Token);
            Check(await initial == "Cookie: sessionid=FAKE_LOCAL_TEST", "Initial host must receive its cookie");
            Check(await redirected == "", "Actual HTTP redirect leaked a cookie to another host");
            Check(await response.Content.ReadAsStringAsync(timeout.Token) == "OK", "Redirected video body must remain readable");
        }
        finally { first.Stop(); second.Stop(); }
    }
}
