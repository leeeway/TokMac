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
byte[] mp4 = File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "tiny.mp4"));
byte[] mov = File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "tiny.mov"));
var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
Directory.CreateDirectory(directory);
try
{
    var target = Path.Combine(directory, "O'Connor.mp4");
    File.WriteAllText(target, "original");
    var temporary = DownloadFile.TemporaryPath(target);
    Check(Path.GetDirectoryName(temporary) == directory, "Temporary download must stay on destination volume");
    File.WriteAllBytes(temporary, mp4);
    DownloadFile.Commit(temporary, target);
    Check(File.ReadAllBytes(target).AsSpan().SequenceEqual(mp4), "Successful download must replace original");
    Check(!File.Exists(temporary), "Successful commit must consume temporary file");
    File.WriteAllText(temporary, "");
    try { DownloadFile.Commit(temporary, target); throw new Exception("Empty video must fail"); }
    catch (IOException) { }
    Check(File.ReadAllBytes(target).AsSpan().SequenceEqual(mp4), "Failed download must preserve original");
    DownloadFile.Cleanup(temporary);
    try { DownloadFile.Commit(temporary, target); throw new Exception("Missing video must fail"); }
    catch (IOException) { }
    Check(File.ReadAllBytes(target).AsSpan().SequenceEqual(mp4), "Missing temporary file must preserve original");
    var directoryTarget = Path.Combine(directory, "existing-directory.mp4");
    Directory.CreateDirectory(directoryTarget);
    File.WriteAllText(Path.Combine(directoryTarget, "sentinel"), "original");
    File.WriteAllBytes(temporary, mp4);
    try { DownloadFile.Commit(temporary, directoryTarget); throw new Exception("Replacing directory must fail"); }
    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    Check(File.ReadAllText(Path.Combine(directoryTarget, "sentinel")) == "original", "Failed replacement must preserve destination");
    Check(File.ReadAllBytes(temporary).AsSpan().SequenceEqual(mp4), "Failed replacement must preserve downloaded bytes");
    File.WriteAllText(temporary, "{\"error\":\"Not video\"}");
    try { DownloadFile.Commit(temporary, target); throw new Exception("JSON bytes must fail"); }
    catch (IOException) { }
    File.WriteAllBytes(temporary, mp4[..^1]);
    try { DownloadFile.Commit(temporary, target); throw new Exception("Truncated MP4 must fail"); }
    catch (IOException) { }
    Check(File.ReadAllBytes(target).AsSpan().SequenceEqual(mp4), "Invalid content must preserve original");
    var corrected = Path.ChangeExtension(target, ".mov");
    File.WriteAllText(corrected, "existing MOV");
    File.WriteAllBytes(temporary, mov);
    try { DownloadFile.Commit(temporary, target); throw new Exception("Renaming must not clobber a different file"); }
    catch (IOException) { }
    Check(File.ReadAllText(corrected) == "existing MOV", "Extension correction must preserve unselected files");
    File.Delete(corrected);
    Check(DownloadFile.Commit(temporary, target) == corrected, "QuickTime files must get .mov extension");
    Check(File.ReadAllBytes(corrected).AsSpan().SequenceEqual(mov), "Saved movie bytes differ");
    byte[] webm = Convert.FromHexString("1A45DFA3874282847765626D18538067FF1654AE6B85AE838381011F43B67583E78100");
    File.WriteAllBytes(temporary, webm);
    Check(Path.GetExtension(DownloadFile.Commit(temporary, target)) == ".webm", "WebM files must get .webm extension");
    Check(File.ReadAllBytes(target).AsSpan().SequenceEqual(mp4), "Corrected files must preserve the initially selected file");
    Console.WriteLine("Windows download validation and atomic-save checks passed.");
}
finally { Directory.Delete(directory, true); }
await DownloadHttpTests.Run();
