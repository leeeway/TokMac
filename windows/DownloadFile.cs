using System;
using System.IO;

namespace TokMac;

internal static class DownloadFile
{
    internal static bool IsTrustedPage(Uri? url) => url != null && url.Scheme == "https" &&
        (url.Host.Equals("tiktok.com", StringComparison.OrdinalIgnoreCase) ||
         url.Host.EndsWith(".tiktok.com", StringComparison.OrdinalIgnoreCase));

    internal static bool IsVideoSource(Uri url, Uri? page)
    {
        if (url.Scheme == "https" || url.Scheme == "http") return url.Host.Length > 0 && url.UserInfo.Length == 0;
        return url.Scheme == "blob" && IsTrustedPage(page) &&
            Uri.TryCreate(url.AbsoluteUri.Substring(5), UriKind.Absolute, out var origin) &&
            origin.GetLeftPart(UriPartial.Authority) == page!.GetLeftPart(UriPartial.Authority);
    }

    internal static bool IsVideoMime(string? mime, bool allowEmpty = false) =>
        (allowEmpty && string.IsNullOrEmpty(mime)) ||
        (mime?.StartsWith("video/", StringComparison.OrdinalIgnoreCase) ?? false) ||
        string.Equals(mime, "application/octet-stream", StringComparison.OrdinalIgnoreCase) ||
        string.Equals(mime, "application/mp4", StringComparison.OrdinalIgnoreCase);

    internal static string TemporaryPath(string destination) =>
        Path.Combine(Path.GetDirectoryName(Path.GetFullPath(destination))!, $".tokmac-{Guid.NewGuid()}.part");

    internal static string Commit(string temporary, string destination)
    {
        var extension = "." + VideoContainer.GetExtension(temporary);
        if (!Path.GetExtension(destination).Equals(extension, StringComparison.OrdinalIgnoreCase))
        {
            var corrected = Path.ChangeExtension(destination, extension);
            // An extension correction is not permission to replace another file.
            File.Move(temporary, corrected);
            return corrected;
        }
        // Temporary files live beside their destination, so replacement stays on one volume.
        // Failure leaves the existing destination intact.
        if (File.Exists(destination)) File.Replace(temporary, destination, null);
        else File.Move(temporary, destination);
        return destination;
    }

    internal static void Cleanup(string temporary)
    {
        try { File.Delete(temporary); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
