using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace TokMac;

internal sealed class SavedVideo
{
    internal const int MaxThumbnailBytes = 48 * 1024;
    private static readonly Regex VideoPath = new(@"\A/@([A-Za-z0-9._]{1,64})/video/([0-9]{1,32})/?\z", RegexOptions.CultureInvariant);
    private static readonly Regex Whitespace = new(@"\s+", RegexOptions.CultureInvariant);

    private SavedVideo(Uri url, string author, string id, string? caption, byte[]? thumbnail)
    {
        Url = url;
        Id = id;
        Author = $"@{author}";
        string normalized = Whitespace.Replace(caption?[..Math.Min(caption.Length, 1024)] ?? "", " ").Trim();
        if (normalized.Length > 300)
            normalized = normalized[..(char.IsHighSurrogate(normalized[299]) ? 299 : 300)];
        Caption = normalized.Length == 0 ? null : normalized;
        Thumbnail = thumbnail is { Length: > 0 and <= MaxThumbnailBytes } ? thumbnail : null;
    }

    public Uri Url { get; }
    public string Id { get; }
    public string Author { get; }
    public string? Caption { get; }
    public byte[]? Thumbnail { get; }
    public string Title => Caption ?? $"视频 {Id}";
    public string Subtitle => $"{Author} · {Id}";
    public bool NeedsDetails => Caption == null || Thumbnail == null;

    internal bool Matches(string query)
    {
        string searchable = $"{Caption} {Author} {Id}";
        return query.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
            .All(term => searchable.Contains(term, StringComparison.CurrentCultureIgnoreCase));
    }

    internal SavedVideo Merge(SavedVideo update) =>
        new(update.Url, update.Author[1..], Id, update.Caption ?? Caption, update.Thumbnail ?? Thumbnail);

    internal static SavedVideo? Parse(string? value, string? caption = null, byte[]? thumbnail = null)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var url) || !DownloadFile.IsTrustedPage(url) ||
            !url.IsDefaultPort || url.UserInfo.Length != 0) return null;
        var match = VideoPath.Match(url.AbsolutePath);
        if (!match.Success) return null;
        string author = match.Groups[1].Value;
        string id = match.Groups[2].Value;
        return new SavedVideo(new Uri($"https://www.tiktok.com/@{author}/video/{id}"), author, id, caption, thumbnail);
    }
}

internal sealed record WatchLaterDetails(string? Url, string? Title, string? ThumbnailUrl)
{
    internal SavedVideo? Video => SavedVideo.Parse(Url, Title);
}

internal sealed class WatchLaterStore(string file)
{
    private sealed record Record(string Url, string? Title, byte[]? Thumbnail);

    internal IReadOnlyList<SavedVideo> Videos()
    {
        try
        {
            using var stream = File.OpenRead(file);
            using var json = JsonDocument.Parse(stream);
            if (json.RootElement.ValueKind != JsonValueKind.Array) throw new InvalidDataException("收藏文件内容无效");
            var rows = json.RootElement.EnumerateArray();
            bool legacy = rows.MoveNext() && rows.Current.ValueKind == JsonValueKind.String;
            return json.RootElement.EnumerateArray().Select(item =>
            {
                var record = legacy && item.ValueKind == JsonValueKind.String
                    ? new Record(item.GetString()!, null, null)
                    : !legacy && item.ValueKind == JsonValueKind.Object
                        ? item.Deserialize<Record>(JsonSerializerOptions.Web) : null;
                return SavedVideo.Parse(record?.Url, record?.Title, record?.Thumbnail)
                    ?? throw new InvalidDataException("收藏文件含无效条目");
            })
                .DistinctBy(video => video.Id).ToArray();
        }
        catch (FileNotFoundException) { return []; }
        catch (DirectoryNotFoundException) { return []; }
    }

    internal bool Add(SavedVideo video)
    {
        var entries = Videos().ToList();
        int index = entries.FindIndex(existing => existing.Id == video.Id);
        if (index >= 0)
        {
            Update(video, index, entries);
            return false;
        }
        entries.Insert(0, video);
        Write(entries);
        return true;
    }

    internal void Refresh(SavedVideo video)
    {
        var entries = Videos().ToList();
        int index = entries.FindIndex(existing => existing.Id == video.Id);
        if (index >= 0) Update(video, index, entries);
    }

    internal void RefreshThumbnail(string id, byte[] data)
    {
        var entries = Videos().ToList();
        int index = entries.FindIndex(existing => existing.Id == id);
        if (index >= 0 && SavedVideo.Parse(entries[index].Url.AbsoluteUri, thumbnail: data) is { } update)
            Update(update, index, entries);
    }

    internal void Remove(SavedVideo video)
    {
        var entries = Videos();
        var remaining = entries.Where(existing => existing.Id != video.Id).ToArray();
        if (remaining.Length != entries.Count) Write(remaining);
    }

    private void Update(SavedVideo video, int index, List<SavedVideo> entries)
    {
        var existing = entries[index];
        var merged = existing.Merge(video);
        if (existing.Url == merged.Url && existing.Caption == merged.Caption &&
            (existing.Thumbnail == null) == (merged.Thumbnail == null) &&
            existing.Thumbnail.AsSpan().SequenceEqual(merged.Thumbnail)) return;
        entries[index] = merged;
        Write(entries);
    }

    private void Write(IEnumerable<SavedVideo> entries)
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(file))!;
        Directory.CreateDirectory(directory);
        var temporary = DownloadFile.TemporaryPath(file);
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew))
                JsonSerializer.Serialize(stream, entries.Select(video => new Record(video.Url.AbsoluteUri, video.Caption, video.Thumbnail)),
                    JsonSerializerOptions.Web);
            File.Move(temporary, file, overwrite: true);
        }
        finally { DownloadFile.Cleanup(temporary); }
    }
}
