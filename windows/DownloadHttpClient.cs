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

    public void Dispose() => client.Dispose();
}
