using System;
using System.IO;
using TokMac;

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

var page = new Uri("https://www.tiktok.com/foryou");
Check(DownloadFile.IsTrustedPage(page), "TikTok must be trusted");
Check(!DownloadFile.IsTrustedPage(new Uri("https://tiktok.com.evil.example")), "Suffix spoof must be rejected");
Check(!DownloadFile.IsTrustedPage(new Uri("http://tiktok.com")), "Insecure page must be rejected");
Check(DownloadFile.IsVideoSource(new Uri("blob:https://www.tiktok.com/id"), page), "Same-origin Blob must work");
Check(!DownloadFile.IsVideoSource(new Uri("blob:https://evil.example/id"), page), "Foreign Blob must be rejected");
Check(!DownloadFile.IsVideoSource(new Uri("file:///etc/passwd"), page), "File URL must be rejected");
Check(DownloadFile.IsVideoMime("video/mp4"), "Video mime must work");
Check(!DownloadFile.IsVideoMime("text/html"), "Error HTML must be rejected");
Check(!DownloadFile.IsVideoMime("application/json"), "Error JSON must be rejected");
var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
Directory.CreateDirectory(directory);
try
{
    var target = Path.Combine(directory, "O'Connor.mp4");
    File.WriteAllText(target, "original");
    var temporary = DownloadFile.TemporaryPath(target);
    Check(Path.GetDirectoryName(temporary) == directory, "Temporary download must stay on destination volume");
    File.WriteAllText(temporary, "new video");
    DownloadFile.Commit(temporary, target);
    Check(File.ReadAllText(target) == "new video", "Successful download must replace original");
    Check(!File.Exists(temporary), "Successful commit must consume temporary file");
    File.WriteAllText(temporary, "");
    try { DownloadFile.Commit(temporary, target); throw new Exception("Empty video must fail"); }
    catch (IOException) { }
    Check(File.ReadAllText(target) == "new video", "Failed download must preserve original");
    DownloadFile.Cleanup(temporary);
    try { DownloadFile.Commit(temporary, target); throw new Exception("Missing video must fail"); }
    catch (IOException) { }
    Check(File.ReadAllText(target) == "new video", "Missing temporary file must preserve original");
    var directoryTarget = Path.Combine(directory, "existing-directory");
    Directory.CreateDirectory(directoryTarget);
    File.WriteAllText(Path.Combine(directoryTarget, "sentinel"), "original");
    File.WriteAllText(temporary, "video");
    try { DownloadFile.Commit(temporary, directoryTarget); throw new Exception("Replacing directory must fail"); }
    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    Check(File.ReadAllText(Path.Combine(directoryTarget, "sentinel")) == "original", "Failed replacement must preserve destination");
    Check(File.ReadAllText(temporary) == "video", "Failed replacement must preserve downloaded bytes");
    Console.WriteLine("Windows download validation and atomic-save checks passed.");
}
finally { Directory.Delete(directory, true); }
