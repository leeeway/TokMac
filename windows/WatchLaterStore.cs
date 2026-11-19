using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace TokMac;

internal sealed class SavedVideo
{
    private static readonly Regex VideoPath = new(@"\A/@([A-Za-z0-9._]{1,64})/video/([0-9]{1,32})/?\z", RegexOptions.CultureInvariant);

    private SavedVideo(Uri url, string author, string id)
    {
        Url = url;
        Id = id;
        Title = $"@{author} · {id}";
    }

    public Uri Url { get; }
    public string Id { get; }
    public string Title { get; }

    internal static SavedVideo? Parse(string? value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var url) || !DownloadFile.IsTrustedPage(url) ||
            !url.IsDefaultPort || url.UserInfo.Length != 0) return null;
        var match = VideoPath.Match(url.AbsolutePath);
        if (!match.Success) return null;
        string author = match.Groups[1].Value;
        string id = match.Groups[2].Value;
        return new SavedVideo(new Uri($"https://www.tiktok.com/@{author}/video/{id}"), author, id);
    }
}

internal sealed class WatchLaterStore(string file)
{
    internal IReadOnlyList<SavedVideo> Videos()
    {
        try
        {
            using var stream = File.OpenRead(file);
            var urls = JsonSerializer.Deserialize<string[]>(stream) ?? throw new InvalidDataException("收藏文件内容无效");
            return urls.Select(url => SavedVideo.Parse(url) ?? throw new InvalidDataException("收藏文件含无效链接"))
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
            if (entries[index].Url != video.Url)
            {
                entries[index] = video;
                Write(entries);
            }
            return false;
        }
        entries.Insert(0, video);
        Write(entries);
        return true;
    }

    internal void Remove(SavedVideo video)
    {
        var entries = Videos();
        var remaining = entries.Where(existing => existing.Id != video.Id).ToArray();
        if (remaining.Length != entries.Count) Write(remaining);
    }

    private void Write(IEnumerable<SavedVideo> entries)
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(file))!;
        Directory.CreateDirectory(directory);
        var temporary = DownloadFile.TemporaryPath(file);
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew))
                JsonSerializer.Serialize(stream, entries.Select(video => video.Url.AbsoluteUri));
            File.Move(temporary, file, overwrite: true);
        }
        finally { DownloadFile.Cleanup(temporary); }
    }
}
