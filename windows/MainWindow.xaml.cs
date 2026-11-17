using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Shell;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Win32;

namespace TokMac
{
    public partial class MainWindow : Window
    {
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
        private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

        private bool isCompactMode = false;
        private string? currentDownloadedFilePath;
        private Guid? activeDownloadID;
        private BlobRequest? pendingBlob;
        private bool isCommittingDownload;

        private sealed class BlobRequest
        {
            public required string Url { get; init; }
            public required string TemporaryPath { get; init; }
            public CoreWebView2DownloadOperation? Operation { get; set; }
            public TaskCompletionSource<bool> Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
            public TaskCompletionSource<bool> Completed { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
            public EventHandler<object>? ProgressHandler { get; set; }
            public EventHandler<object>? StateHandler { get; set; }
        }
        private DispatcherTimer? autoDismissTimer;
        private CancellationTokenSource? downloadCts;

        public MainWindow()
        {
            InitializeComponent();
            Loaded += MainWindow_Loaded;
            KeyDown += MainWindow_KeyDown;
            Closed += (_, _) =>
            {
                downloadCts?.Cancel();
                pendingBlob?.Operation?.Cancel();
                autoDismissTimer?.Stop();
                webView.Dispose();
            };
        }

        private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            EnableDarkModeTitleBar();
            await InitializeWebView();
        }

        private void EnableDarkModeTitleBar()
        {
            try
            {
                var helper = new WindowInteropHelper(this);
                int darkMode = 1;
                DwmSetWindowAttribute(helper.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, ref darkMode, sizeof(int));
            }
            catch { }
        }

        private async Task InitializeWebView()
        {
            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string userDataFolder = Path.Combine(localAppData, "TokMac", "WebView2Data");
                Directory.CreateDirectory(userDataFolder);

                var environment = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
                await webView.EnsureCoreWebView2Async(environment);

                webView.CoreWebView2.Settings.IsStatusBarEnabled = false;
                webView.CoreWebView2.Settings.AreDevToolsEnabled = true;
                webView.CoreWebView2.Settings.UserAgent =
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0";

                // The same script is embedded by both native clients.
                using var scriptStream = typeof(MainWindow).Assembly.GetManifestResourceStream("TokMac.tokmac.js")
                    ?? throw new InvalidOperationException("Missing bundled tokmac.js");
                using var scriptReader = new StreamReader(scriptStream);
                await webView.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(await scriptReader.ReadToEndAsync());
                // No JavaScript message handler exposes local file writes.
                webView.CoreWebView2.Settings.IsWebMessageEnabled = false;
                webView.CoreWebView2.DownloadStarting += CoreWebView2_DownloadStarting;
                webView.CoreWebView2.ContextMenuRequested += (_, args) =>
                {
                    var item = environment.CreateContextMenuItem("下载当前视频 (Ctrl+S)", null, CoreWebView2ContextMenuItemKind.Command);
                    item.CustomItemSelected += async (_, _) => await TriggerVideoDownloadAsync();
                    args.MenuItems.Insert(0, item);
                };
                webView.CoreWebView2.Navigate("https://www.tiktok.com/");
            }
            catch (Exception ex)
            {
                MessageBox.Show($"WebView2 初始化失败: {ex.Message}\n请确保已安装 Microsoft Edge WebView2 运行时。", "TokMac 错误", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void CoreWebView2_DownloadStarting(object? sender, CoreWebView2DownloadStartingEventArgs e)
        {
            var request = pendingBlob;
            var operation = e.DownloadOperation;
            // Only the exact Blob selected by the user may use the pre-approved destination.
            if (request == null || request.Operation != null || operation.Uri != request.Url ||
                !DownloadFile.IsTrustedPage(webView.Source) || downloadCts?.IsCancellationRequested != false)
            {
                e.Cancel = true;
                e.Handled = true;
                return;
            }
            if (!DownloadFile.IsVideoMime(operation.MimeType, allowEmpty: true))
            {
                e.Cancel = true;
                e.Handled = true;
                request.Started.TrySetException(new IOException("视频流返回了不支持的内容类型"));
                return;
            }
            request.Operation = operation;
            e.Handled = true;
            e.ResultFilePath = request.TemporaryPath;
            request.ProgressHandler = (_, _) =>
            {
                if (pendingBlob != request || downloadCts?.IsCancellationRequested != false) return;
                long total = (long)Math.Min(operation.TotalBytesToReceive ?? 0, (ulong)long.MaxValue);
                if (total > 0) UpdateHUDProgress((double)operation.BytesReceived / total, operation.BytesReceived, total);
            };
            request.StateHandler = (_, _) =>
            {
                if (operation.State == CoreWebView2DownloadState.Completed) request.Completed.TrySetResult(true);
                else if (operation.State == CoreWebView2DownloadState.Interrupted)
                    request.Completed.TrySetException(new IOException("视频流下载中断: " + operation.InterruptReason));
            };
            operation.BytesReceivedChanged += request.ProgressHandler;
            operation.StateChanged += request.StateHandler;
            request.Started.TrySetResult(true);
        }

        // MARK: - Actions
        private async void BtnDownload_Click(object sender, RoutedEventArgs e)
        {
            await TriggerVideoDownloadAsync();
        }

        private async Task TriggerVideoDownloadAsync()
        {
            if (webView.CoreWebView2 == null || activeDownloadID != null || !DownloadFile.IsTrustedPage(webView.Source)) return;
            var id = Guid.NewGuid();
            activeDownloadID = id;
            using var cts = new CancellationTokenSource();
            downloadCts = cts;
            btnDownload.IsEnabled = false;
            try
            {
                var page = webView.Source;
                string json = await webView.CoreWebView2.ExecuteScriptAsync("window.tokmacGetVideoDownloadInfo && window.tokmacGetVideoDownloadInfo();");
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;
                if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("url", out var value) ||
                    !Uri.TryCreate(value.GetString(), UriKind.Absolute, out var url) || !DownloadFile.IsVideoSource(url, page))
                    throw new IOException("未检测到当前视频，请等待视频加载后重试");
                string author = root.TryGetProperty("author", out var auth) ? auth.GetString() ?? "TikTok" : "TikTok";
                foreach (char c in Path.GetInvalidFileNameChars()) author = author.Replace(c, '_');
                var dialog = new SaveFileDialog
                {
                    Title = "选择保存视频的位置",
                    Filter = "MP4 视频 (*.mp4)|*.mp4|所有文件 (*.*)|*.*",
                    FileName = $"{author}_{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}.mp4",
                    InitialDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads")
                };
                if (dialog.ShowDialog(this) != true) return;
                cts.Token.ThrowIfCancellationRequested();
                if (webView.Source != page) throw new IOException("页面已切换，请重新选择视频");
                if (url.Scheme == "blob") await PerformBlobDownloadAsync(url.AbsoluteUri, dialog.FileName, cts.Token);
                else await PerformDirectDownloadAsync(url.AbsoluteUri, dialog.FileName, cts.Token);
                FinishHUD(dialog.FileName);
            }
            catch (OperationCanceledException) { HideHUD(); }
            catch (Exception) when (cts.IsCancellationRequested) { HideHUD(); }
            catch (Exception ex) { ShowHUDError("下载失败: " + ex.Message); }
            finally
            {
                if (activeDownloadID == id)
                {
                    activeDownloadID = null;
                    downloadCts = null;
                    isCommittingDownload = false;
                    btnDownload.IsEnabled = true;
                }
            }
        }

        private async Task CommitDownloadAsync(string temporary, string destination, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            isCommittingDownload = true;
            await Task.Run(() => DownloadFile.Commit(temporary, destination));
        }

        private async Task PerformDirectDownloadAsync(string url, string destination, CancellationToken token)
        {
            string temporary = DownloadFile.TemporaryPath(destination);
            ShowHUDStart(Path.GetFileName(destination));
            try
            {
                using var client = new HttpClient();
                client.DefaultRequestHeaders.Add("Referer", "https://www.tiktok.com/");
                client.DefaultRequestHeaders.Add("User-Agent", webView.CoreWebView2.Settings.UserAgent);
                var cookies = await webView.CoreWebView2.CookieManager.GetCookiesAsync(url);
                if (cookies.Count > 0)
                    client.DefaultRequestHeaders.Add("Cookie", string.Join("; ", System.Linq.Enumerable.Select(cookies, c => c.Name + "=" + c.Value)));
                using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, token);
                response.EnsureSuccessStatusCode();
                if (!DownloadFile.IsVideoMime(response.Content.Headers.ContentType?.MediaType))
                    throw new IOException("服务器返回的内容不是视频");
                long total = response.Content.Headers.ContentLength ?? 0;
                await using (var input = await response.Content.ReadAsStreamAsync(token))
                await using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, true))
                {
                    var buffer = new byte[65536];
                    long written = 0;
                    var lastUpdate = Stopwatch.StartNew();
                    int count;
                    while ((count = await input.ReadAsync(buffer.AsMemory(), token)) > 0)
                    {
                        await output.WriteAsync(buffer.AsMemory(0, count), token);
                        written += count;
                        if (total > 0 && (lastUpdate.ElapsedMilliseconds >= 100 || written == total))
                        {
                            UpdateHUDProgress((double)written / total, written, total);
                            lastUpdate.Restart();
                        }
                    }
                    if (total > 0 && written != total) throw new IOException("视频下载不完整");
                    await output.FlushAsync(token);
                }
                await CommitDownloadAsync(temporary, destination, token);
            }
            finally { DownloadFile.Cleanup(temporary); }
        }

        private async Task PerformBlobDownloadAsync(string url, string destination, CancellationToken token)
        {
            var request = new BlobRequest { Url = url, TemporaryPath = DownloadFile.TemporaryPath(destination) };
            pendingBlob = request;
            ShowHUDIndeterminate("正在提取视频流...", Path.GetFileName(destination));
            try
            {
                // JSON encoding also handles apostrophes, backslashes, and line breaks.
                await webView.CoreWebView2.ExecuteScriptAsync($"window.tokmacDownloadBlob({JsonSerializer.Serialize(url)});");
                await request.Started.Task.WaitAsync(TimeSpan.FromSeconds(15), token);
                await request.Completed.Task.WaitAsync(token);
                await CommitDownloadAsync(request.TemporaryPath, destination, token);
            }
            finally
            {
                if (request.Operation is { } operation)
                {
                    if (operation.State == CoreWebView2DownloadState.InProgress)
                    {
                        operation.Cancel();
                        try { await request.Completed.Task.WaitAsync(TimeSpan.FromSeconds(5)); } catch { }
                    }
                    operation.BytesReceivedChanged -= request.ProgressHandler;
                    operation.StateChanged -= request.StateHandler;
                }
                if (pendingBlob == request) pendingBlob = null;
                DownloadFile.Cleanup(request.TemporaryPath);
            }
        }

        // MARK: - HUD UI Controls
        private void ShowHUDStart(string filename)
        {
            autoDismissTimer?.Stop();
            currentDownloadedFilePath = null;

            hudIcon.Text = "⬇️";
            hudTitle.Text = "正在下载视频 (0%)...";
            hudSubtitle.Text = filename;
            hudProgressBar.IsIndeterminate = false;
            hudProgressBar.Value = 0;
            hudProgressBar.Visibility = Visibility.Visible;
            hudRevealBtn.Visibility = Visibility.Collapsed;

            downloadHUD.Visibility = Visibility.Visible;
            taskbarInfo.ProgressState = TaskbarItemProgressState.Indeterminate;
            taskbarInfo.ProgressValue = 0;
            hudProgressBar.IsIndeterminate = true;
        }

        private void UpdateHUDProgress(double fraction, long writtenBytes, long totalBytes)
        {
            fraction = Math.Clamp(fraction, 0, 1);
            hudProgressBar.IsIndeterminate = false;
            taskbarInfo.ProgressState = TaskbarItemProgressState.Normal;
            int percent = (int)(fraction * 100);
            hudTitle.Text = $"正在下载视频 ({percent}%)";
            hudSubtitle.Text = $"{FormatBytes(writtenBytes)} / {FormatBytes(totalBytes)}";
            hudProgressBar.Value = percent;

            taskbarInfo.ProgressValue = fraction;
        }

        private void ShowHUDIndeterminate(string title, string subtitle)
        {
            autoDismissTimer?.Stop();
            currentDownloadedFilePath = null;
            hudIcon.Text = "⬇️";
            hudTitle.Text = title;
            hudSubtitle.Text = subtitle;
            hudProgressBar.IsIndeterminate = true;
            hudProgressBar.Visibility = Visibility.Visible;
            hudRevealBtn.Visibility = Visibility.Collapsed;

            downloadHUD.Visibility = Visibility.Visible;
            taskbarInfo.ProgressState = TaskbarItemProgressState.Indeterminate;
        }

        private void FinishHUD(string filePath)
        {
            currentDownloadedFilePath = filePath;
            hudIcon.Text = "🎉";
            hudTitle.Text = "视频下载完成！";
            hudSubtitle.Text = Path.GetFileName(filePath);
            hudProgressBar.Visibility = Visibility.Collapsed;
            hudRevealBtn.Visibility = Visibility.Visible;

            taskbarInfo.ProgressState = TaskbarItemProgressState.None;

            try
            {
                System.Media.SystemSounds.Asterisk.Play();
            }
            catch { }

            autoDismissTimer?.Stop();
            autoDismissTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
            autoDismissTimer.Tick += (s, e) =>
            {
                autoDismissTimer.Stop();
                HideHUD();
            };
            autoDismissTimer.Start();
        }

        private void ShowHUDError(string error)
        {
            hudIcon.Text = "⚠️";
            hudTitle.Text = "下载遇到问题";
            hudSubtitle.Text = error;
            hudProgressBar.Visibility = Visibility.Collapsed;
            hudRevealBtn.Visibility = Visibility.Collapsed;

            downloadHUD.Visibility = Visibility.Visible;
            taskbarInfo.ProgressState = TaskbarItemProgressState.Error;

            autoDismissTimer?.Stop();
            autoDismissTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
            autoDismissTimer.Tick += (s, e) =>
            {
                autoDismissTimer.Stop();
                HideHUD();
            };
            autoDismissTimer.Start();
        }

        private void HideHUD()
        {
            downloadHUD.Visibility = Visibility.Collapsed;
            taskbarInfo.ProgressState = TaskbarItemProgressState.None;
        }

        private void HudCloseBtn_Click(object sender, RoutedEventArgs e)
        {
            if (!isCommittingDownload)
            {
                downloadCts?.Cancel();
                pendingBlob?.Operation?.Cancel();
            }
            HideHUD();
        }

        private void HudRevealBtn_Click(object sender, RoutedEventArgs e)
        {
            if (!string.IsNullOrEmpty(currentDownloadedFilePath) && File.Exists(currentDownloadedFilePath))
            {
                Process.Start("explorer.exe", $"/select,\"{currentDownloadedFilePath}\"");
            }
            HideHUD();
        }

        private string FormatBytes(long bytes)
        {
            string[] sizes = { "B", "KB", "MB", "GB" };
            double len = bytes;
            int order = 0;
            while (len >= 1024 && order < sizes.Length - 1)
            {
                order++;
                len /= 1024;
            }
            return $"{len:0.#} {sizes[order]}";
        }

        // MARK: - Toolbar Actions
        private void BtnPin_Click(object sender, RoutedEventArgs e)
        {
            Topmost = !Topmost;
            btnPin.Content = Topmost ? "📌 已置顶" : "📌 置顶";
            btnPin.Background = Topmost ? System.Windows.Media.Brushes.DarkSlateGray : (System.Windows.Media.Brush)FindResource("BarDark");
        }

        private void BtnLayout_Click(object sender, RoutedEventArgs e)
        {
            isCompactMode = !isCompactMode;
            if (isCompactMode)
            {
                Width = 520;
                Height = 840;
                btnLayout.Content = "💻 桌面模式";
            }
            else
            {
                Width = 1080;
                Height = 760;
                btnLayout.Content = "📱 竖屏小窗";
            }
        }

        private void BtnReload_Click(object sender, RoutedEventArgs e)
        {
            webView.CoreWebView2?.Reload();
        }

        private async void MainWindow_KeyDown(object sender, KeyEventArgs e)
        {
            if (Keyboard.Modifiers == ModifierKeys.Control)
            {
                if (e.Key == Key.S)
                {
                    e.Handled = true;
                    await TriggerVideoDownloadAsync();
                }
                else if (e.Key == Key.T)
                {
                    e.Handled = true;
                    BtnPin_Click(sender, e);
                }
                else if (e.Key == Key.D1 || e.Key == Key.NumPad1)
                {
                    e.Handled = true;
                    if (!isCompactMode) BtnLayout_Click(sender, e);
                }
                else if (e.Key == Key.D2 || e.Key == Key.NumPad2)
                {
                    e.Handled = true;
                    if (isCompactMode) BtnLayout_Click(sender, e);
                }
                else if (e.Key == Key.R)
                {
                    e.Handled = true;
                    BtnReload_Click(sender, e);
                }
            }
            else if (e.Key == Key.F5)
            {
                e.Handled = true;
                BtnReload_Click(sender, e);
            }
            else if (e.Key == Key.F11)
            {
                e.Handled = true;
                WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
            }
        }
    }
}
