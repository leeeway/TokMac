using System;
using System.IO;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace TokMac;

internal sealed class DownloadHttpClient : IDisposable
{
    private readonly HttpClient client;

    internal DownloadHttpClient() : this(new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false }) { }

    // The injectable transport lets regression tests exercise the same redirect policy.
    internal DownloadHttpClient(HttpMessageHandler transport)
    {
        if (transport is HttpClientHandler handler)
        {
            handler.AllowAutoRedirect = false;
            handler.UseCookies = false;
        }
        client = new HttpClient(transport);
    }

    internal async Task<HttpResponseMessage> GetAsync(Uri source, string userAgent,
        Func<Uri, Task<string?>> cookiesForUrl, CancellationToken token)
    {
        var current = source;
        for (int redirects = 0; redirects <= 10; redirects++)
        {
            if (!DownloadFile.IsVideoSource(current, null) ||
                (source.Scheme == "https" && current.Scheme != "https"))
                throw new IOException("视频重定向到了不安全的地址");

            using var request = new HttpRequestMessage(HttpMethod.Get, current);
            request.Headers.TryAddWithoutValidation("User-Agent", userAgent);
            request.Headers.Referrer = new Uri("https://www.tiktok.com/");
            // Query WebView2 for this exact hop, preserving its domain/path/Secure rules.
            // Never reuse a Cookie header or the previous response's cookies across hosts.
            var cookies = await cookiesForUrl(current);
            token.ThrowIfCancellationRequested();
            if (!string.IsNullOrEmpty(cookies)) request.Headers.Add("Cookie", cookies);
            var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            int status = (int)response.StatusCode;
            if (status is not (301 or 302 or 303 or 307 or 308)) return response;

            var location = response.Headers.Location;
            response.Dispose();
            if (location == null) throw new IOException("视频重定向缺少目标地址");
            var next = location.IsAbsoluteUri ? location : new Uri(current, location);
            if (current.Scheme == "https" && next.Scheme != "https")
                throw new IOException("视频重定向不能从 HTTPS 降级到 HTTP");
            current = next;
        }
        throw new IOException("视频重定向次数过多");
    }

    internal static void ValidateVideoResponse(HttpResponseMessage response)
    {
        response.EnsureSuccessStatusCode();
        if ((int)response.StatusCode == 206 || response.Content.Headers.Contains("Content-Range"))
            throw new IOException("服务器只返回了视频片段，未保存视频");
        if (!DownloadFile.IsVideoMime(response.Content.Headers.ContentType?.MediaType))
            throw new IOException("服务器返回的内容不是视频");
    }

    internal static async Task CopyBodyAsync(Stream input, Stream output, long? expectedBytes,
        Action<long> progress, TimeSpan idleTimeout, CancellationToken token)
    {
        using var idle = CancellationTokenSource.CreateLinkedTokenSource(token);
        var buffer = new byte[65536];
        long written = 0;
        while (true)
        {
            int count;
            idle.CancelAfter(idleTimeout);
            try
            {
                count = await input.ReadAsync(buffer.AsMemory(), idle.Token);
                idle.Token.ThrowIfCancellationRequested();
            }
            catch (OperationCanceledException) when (!token.IsCancellationRequested && idle.IsCancellationRequested)
            {
                throw new TimeoutException("视频下载超时，服务器长时间未发送数据");
            }
            finally { idle.CancelAfter(Timeout.InfiniteTimeSpan); }

            if (count == 0) break;
            await output.WriteAsync(buffer.AsMemory(0, count), token);
            written += count;
            progress(written);
        }
        if (expectedBytes.HasValue && written != expectedBytes.Value)
            throw new IOException("视频下载不完整");
    }

    public void Dispose() => client.Dispose();
}
