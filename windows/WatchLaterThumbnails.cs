using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media.Imaging;

namespace TokMac;

internal static class WatchLaterThumbnails
{
    private const int MaxDownloadBytes = 2 * 1024 * 1024;
    private static readonly string[] Domains = ["tiktokcdn.com", "tiktokcdn-us.com", "tiktokcdn-eu.com"];
    private static readonly HttpClient Client = new(new HttpClientHandler
    {
        AllowAutoRedirect = false,
        UseCookies = false
    })
    {
        Timeout = TimeSpan.FromSeconds(8),
        MaxResponseContentBufferSize = MaxDownloadBytes
    };

    internal static Uri? AllowedUrl(string? value)
    {
        if (value is not { Length: <= 4096 } || !Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps || !uri.IsDefaultPort || uri.UserInfo.Length != 0) return null;
        return Domains.Any(domain => uri.Host.Equals(domain, StringComparison.OrdinalIgnoreCase) ||
            uri.Host.EndsWith("." + domain, StringComparison.OrdinalIgnoreCase)) ? uri : null;
    }

    internal static async Task<byte[]?> FetchAsync(string? value)
    {
        if (AllowedUrl(value) is not { } uri) return null;
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, uri);
            request.Headers.Accept.ParseAdd("image/jpeg,image/png,image/webp");
            request.Headers.Referrer = new Uri("https://www.tiktok.com/");
            using var response = await Client.SendAsync(request).ConfigureAwait(false);
            if (response.StatusCode != HttpStatusCode.OK ||
                response.Content.Headers.ContentType?.MediaType is not ("image/jpeg" or "image/png" or "image/webp")) return null;
            var input = await response.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
            return await Task.Run(() => MakeJpeg(input)).ConfigureAwait(false);
        }
        catch (Exception error) when (error is HttpRequestException or OperationCanceledException)
        {
            Debug.WriteLine(error);
            return null;
        }
    }

    internal static byte[]? MakeJpeg(byte[] data)
    {
        var bytes = data.AsSpan();
        if (data.Length > MaxDownloadBytes ||
            !(bytes.StartsWith(new byte[] { 0xff, 0xd8, 0xff }) ||
              bytes.StartsWith(new byte[] { 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a }) ||
              (bytes.Length >= 12 && bytes.StartsWith("RIFF"u8) && bytes[8..].StartsWith("WEBP"u8)))) return null;
        try
        {
            if (ReadBitmap(data) is not { } image) return null;
            var encoder = new JpegBitmapEncoder { QualityLevel = 78 };
            encoder.Frames.Add(BitmapFrame.Create(image));
            using var output = new MemoryStream();
            encoder.Save(output);
            return output.Length <= SavedVideo.MaxThumbnailBytes ? output.ToArray() : null;
        }
        catch (Exception error) when (IsImageError(error))
        {
            Debug.WriteLine(error);
            return null;
        }
    }

    private static BitmapImage? ReadBitmap(byte[] data)
    {
        using var input = new MemoryStream(data);
        var decoder = BitmapDecoder.Create(input, BitmapCreateOptions.DelayCreation, BitmapCacheOption.OnDemand);
        var frame = decoder.Frames[0];
        int width = frame.PixelWidth;
        int height = frame.PixelHeight;
        if (width is < 1 or > 8192 || height is < 1 or > 8192 || width * height > 16_000_000) return null;
        input.Position = 0;
        var image = new BitmapImage();
        image.BeginInit();
        image.StreamSource = input;
        image.CacheOption = BitmapCacheOption.OnLoad;
        if (width >= height) image.DecodePixelWidth = Math.Min(width, 240);
        else image.DecodePixelHeight = Math.Min(height, 240);
        image.EndInit();
        image.Freeze();
        return image;
    }

    internal static BitmapImage? ReadThumbnail(byte[]? jpeg)
    {
        if (jpeg is not { Length: >= 3 and <= SavedVideo.MaxThumbnailBytes } ||
            jpeg[0] != 0xff || jpeg[1] != 0xd8 || jpeg[2] != 0xff) return null;
        try
        {
            return ReadBitmap(jpeg);
        }
        catch (Exception error) when (IsImageError(error))
        {
            Debug.WriteLine(error);
            return null;
        }
    }

    private static bool IsImageError(Exception error) =>
        error is IOException or NotSupportedException or ArgumentException or InvalidOperationException or FormatException or COMException;
}

public sealed class WatchLaterThumbnailConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        (object?)WatchLaterThumbnails.ReadThumbnail(value as byte[]) ?? DependencyProperty.UnsetValue;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}
