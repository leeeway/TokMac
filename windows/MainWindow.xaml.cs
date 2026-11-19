using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Shell;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Win32;

namespace TokMac
{
    public partial class MainWindow : Window
    {
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
        private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

        private bool isCompactMode = false;
        private bool isFullScreen;
        private WindowState savedWindowState;
        private WindowStyle savedWindowStyle;
        private ResizeMode savedResizeMode;
        private Rect savedBounds;
        private GridLength savedToolbarHeight;
        private string? currentDownloadedFilePath;
        private Guid? activeDownloadID;
        private BlobRequest? pendingBlob;
        private bool isCommittingDownload;
        private CoreWebView2? browser;
        private Uri? lastTrustedPage;
        private bool initializingBrowser;
        private bool closing;
        private bool recreateBrowser;
        private DateTimeOffset lastBrowserRecovery;
        private readonly WatchLaterStore watchLater = new(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TokMac", "watch-later.json"));
        private readonly DispatcherTimer videoActionTimer = new() { Interval = TimeSpan.FromSeconds(3) };

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
            PreviewKeyDown += MainWindow_KeyDown;
            videoActionTimer.Tick += (_, _) =>
            {
                videoActionTimer.Stop();
                videoActionStatus.Visibility = Visibility.Collapsed;
            };
            Closed += (_, _) =>
            {
                closing = true;
                browser = null;
                downloadCts?.Cancel();
                autoDismissTimer?.Stop();
                videoActionTimer.Stop();
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
            if (closing || initializingBrowser) return;
            initializingBrowser = true;
            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string userDataFolder = Path.Combine(localAppData, "TokMac", "WebView2Data");
                Directory.CreateDirectory(userDataFolder);

                var environment = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
                if (closing) return;
                await webView.EnsureCoreWebView2Async(environment);
                if (closing) return;
                var core = webView.CoreWebView2;

                core.Settings.IsStatusBarEnabled = false;
                core.Settings.AreDevToolsEnabled = true;
                core.Settings.UserAgent =
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0";

                using var scriptStream = typeof(MainWindow).Assembly.GetManifestResourceStream("TokMac.tokmac.js")
                    ?? throw new InvalidOperationException("Missing bundled tokmac.js");
                using var scriptReader = new StreamReader(scriptStream);
                string script = await scriptReader.ReadToEndAsync();
                if (closing) return;
                await core.AddScriptToExecuteOnDocumentCreatedAsync(script);
                if (closing) return;
                core.Settings.IsWebMessageEnabled = false;
                core.DownloadStarting += CoreWebView2_DownloadStarting;
                core.ContextMenuRequested += (_, args) =>
                {
                    var download = environment.CreateContextMenuItem("下载当前视频 (Ctrl+S)", null, CoreWebView2ContextMenuItemKind.Command);
                    download.CustomItemSelected += async (_, _) => await TriggerVideoDownloadAsync();
                    var save = environment.CreateContextMenuItem("加入稍后看", null, CoreWebView2ContextMenuItemKind.Command);
                    save.CustomItemSelected += async (_, _) => await SaveCurrentVideoAsync();
                    var copy = environment.CreateContextMenuItem("复制当前视频链接", null, CoreWebView2ContextMenuItemKind.Command);
                    copy.CustomItemSelected += async (_, _) => await CopyCurrentVideoLinkAsync();
                    args.MenuItems.Insert(0, copy);
                    args.MenuItems.Insert(0, save);
                    args.MenuItems.Insert(0, download);
                };
                core.SourceChanged += (_, _) =>
                {
                    if (browser == core && Uri.TryCreate(core.Source, UriKind.Absolute, out var page) &&
                        DownloadFile.IsTrustedPage(page)) lastTrustedPage = page;
                };
                core.NavigationCompleted += (_, args) =>
                {
                    if (browser != core) return;
                    if (args.IsSuccess) browserStatus.Visibility = Visibility.Collapsed;
                    else if (args.WebErrorStatus != CoreWebView2WebErrorStatus.OperationCanceled)
                        ShowBrowserError("页面加载失败，请重试。");
                };
                core.ProcessFailed += (_, args) =>
                {
                    var kind = args.ProcessFailedKind;
                    // Return to WebView2 before disposing or reloading a control.
                    Dispatcher.BeginInvoke(new Action(() => BrowserProcessFailed(core, kind)));
                };
                browser = core;
                recreateBrowser = false;
                core.Navigate(lastTrustedPage?.AbsoluteUri ?? "https://www.tiktok.com/");
            }
            catch (Exception ex)
            {
                browser = null;
                recreateBrowser = true;
                if (!closing) ShowBrowserError($"浏览器初始化失败，请确认已安装 WebView2 Runtime。\n{ex.Message}");
            }
            finally { initializingBrowser = false; }
        }

        private void ShowBrowserError(string message)
        {
            browserStatusText.Text = message;
            browserStatus.Visibility = Visibility.Visible;
        }

        private void BrowserProcessFailed(CoreWebView2 source, CoreWebView2ProcessFailedKind kind)
        {
            if (closing || browser != source) return;
            if (kind is not (CoreWebView2ProcessFailedKind.BrowserProcessExited or
                CoreWebView2ProcessFailedKind.RenderProcessExited)) return;

            if (!isCommittingDownload) downloadCts?.Cancel();
            if (kind == CoreWebView2ProcessFailedKind.BrowserProcessExited)
            {
                recreateBrowser = true;
                browser = null;
            }
            if (DateTimeOffset.UtcNow - lastBrowserRecovery < TimeSpan.FromSeconds(30))
            {
                ShowBrowserError("网页进程反复退出，请重新加载。");
                return;
            }
            lastBrowserRecovery = DateTimeOffset.UtcNow;
            ShowBrowserError("网页进程已退出，正在恢复。");
            _ = RecoverBrowserAsync();
        }

        private async Task RecoverBrowserAsync()
        {
            if (closing || initializingBrowser) return;
            if (!recreateBrowser && browser is { } core)
            {
                try { core.Reload(); }
                catch (Exception)
                {
                    browser = null;
                    recreateBrowser = true;
                    ShowBrowserError("网页无法刷新，请重新加载浏览器。");
                }
                return;
            }
            ReplaceBrowserControl();
            await InitializeWebView();
        }

        internal void ReplaceBrowserControl()
        {
            var oldView = webView;
            var replacement = new WebView2CompositionControl();
            browser = null;
            webHost.Children.Remove(oldView);
            webView = replacement;
            webHost.Children.Insert(0, replacement);
            try { oldView.Dispose(); }
            catch (Exception error) when (error is COMException or InvalidOperationException)
            {
                Debug.WriteLine(error); // Native process may already have released the control.
            }
        }

        private void CoreWebView2_DownloadStarting(object? sender, CoreWebView2DownloadStartingEventArgs e)
        {
            var request = pendingBlob;
            var operation = e.DownloadOperation;
            // Only the exact Blob selected by the user may use the pre-approved destination.
            if (sender != browser || request == null || request.Operation != null || operation.Uri != request.Url ||
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
        private void WatchLaterMenu_Click(object sender, RoutedEventArgs e)
        {
            var button = (Button)sender;
            button.ContextMenu.PlacementTarget = button;
            button.ContextMenu.IsOpen = true;
        }

        private async void SaveVideo_Click(object sender, RoutedEventArgs e) => await SaveCurrentVideoAsync();
        private async void CopyVideoLink_Click(object sender, RoutedEventArgs e) => await CopyCurrentVideoLinkAsync();
        private async void ShowWatchLater_Click(object sender, RoutedEventArgs e) => await ShowWatchLaterAsync();

        private async Task<SavedVideo?> ResolveCurrentVideoAsync()
        {
            var core = browser;
            var page = webView.Source;
            if (core != null && DownloadFile.IsTrustedPage(page) && browserStatus.Visibility != Visibility.Visible)
            {
                try
                {
                    string result = await core.ExecuteScriptAsync("window.tokmacCurrentVideoLink?.() ?? null");
                    if (core == browser && Equals(webView.Source, page) &&
                        SavedVideo.Parse(JsonSerializer.Deserialize<string>(result)) is { } video)
                        return video;
                }
                catch (Exception error) when (error is COMException or InvalidOperationException or JsonException)
                {
                    Debug.WriteLine(error);
                }
            }
            ShowVideoActionStatus("当前视频没有可用链接");
            return null;
        }

        private async Task SaveCurrentVideoAsync()
        {
            if (await ResolveCurrentVideoAsync() is not { } video) return;
            try { ShowVideoActionStatus(watchLater.Add(video) ? "已加入稍后看" : "视频已在稍后看中"); }
            catch (Exception error)
            {
                Debug.WriteLine(error);
                ShowVideoActionStatus("无法保存到稍后看");
            }
        }

        private async Task CopyCurrentVideoLinkAsync()
        {
            if (await ResolveCurrentVideoAsync() is not { } video) return;
            try
            {
                Clipboard.SetText(video.Url.AbsoluteUri);
                ShowVideoActionStatus("已复制当前视频链接");
            }
            catch (ExternalException error)
            {
                Debug.WriteLine(error);
                ShowVideoActionStatus("无法写入剪贴板");
            }
        }

        private async Task ShowWatchLaterAsync()
        {
            var dialog = new WatchLaterWindow(watchLater) { Owner = this };
            if (dialog.ShowDialog() != true || dialog.SelectedVideo is not { } video) return;
            lastTrustedPage = video.Url;
            try
            {
                if (browser is { } core) core.Navigate(video.Url.AbsoluteUri);
                else await RecoverBrowserAsync();
            }
            catch (Exception error) when (error is COMException or InvalidOperationException)
            {
                Debug.WriteLine(error);
                ShowBrowserError("视频无法打开，请重新加载。");
            }
        }

        private void ShowVideoActionStatus(string message)
        {
            if (closing) return;
            videoActionText.Text = message;
            videoActionStatus.Visibility = Visibility.Visible;
            UIElementAutomationPeer.CreatePeerForElement(videoActionText)?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
            videoActionTimer.Stop();
            videoActionTimer.Start();
        }

        private async void BtnDownload_Click(object sender, RoutedEventArgs e)
        {
            await TriggerVideoDownloadAsync();
        }

        private async Task TriggerVideoDownloadAsync()
        {
            var core = browser;
            if (core == null || activeDownloadID != null || browserStatus.Visibility == Visibility.Visible ||
                !DownloadFile.IsTrustedPage(webView.Source)) return;
            var id = Guid.NewGuid();
            activeDownloadID = id;
            using var cts = new CancellationTokenSource();
            downloadCts = cts;
            btnDownload.IsEnabled = false;
            try
            {
                var page = webView.Source;
                string json = await core.ExecuteScriptAsync("window.tokmacGetVideoDownloadInfo && window.tokmacGetVideoDownloadInfo();").WaitAsync(cts.Token);
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
                    Filter = "视频文件 (*.mp4;*.mov;*.webm)|*.mp4;*.mov;*.webm|所有文件 (*.*)|*.*",
                    FileName = $"{author}_{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}.mp4",
                    InitialDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads")
                };
                if (dialog.ShowDialog(this) != true) return;
                cts.Token.ThrowIfCancellationRequested();
                if (webView.Source != page) throw new IOException("页面已切换，请重新选择视频");
                var savedPath = url.Scheme == "blob"
                    ? await PerformBlobDownloadAsync(core, url.AbsoluteUri, dialog.FileName, cts.Token)
                    : await PerformDirectDownloadAsync(core, url.AbsoluteUri, dialog.FileName, cts.Token);
                FinishHUD(savedPath);
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

        private async Task<string> CommitDownloadAsync(string temporary, string destination, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            isCommittingDownload = true;
            return await Task.Run(() => DownloadFile.Commit(temporary, destination));
        }

        private async Task<string> PerformDirectDownloadAsync(CoreWebView2 core, string url, string destination, CancellationToken token)
        {
            string temporary = DownloadFile.TemporaryPath(destination);
            ShowHUDStart(Path.GetFileName(destination));
            try
            {
                using var client = new DownloadHttpClient();
                using var response = await client.GetAsync(new Uri(url), core.Settings.UserAgent,
                    async target =>
                    {
                        var cookies = await core.CookieManager.GetCookiesAsync(target.AbsoluteUri).WaitAsync(token);
                        return string.Join("; ", System.Linq.Enumerable.Select(cookies, c => c.Name + "=" + c.Value));
                    }, token);
                DownloadHttpClient.ValidateVideoResponse(response);
                long? expectedBytes = response.Content.Headers.ContentLength;
                long total = expectedBytes ?? 0;
                await using (var input = await response.Content.ReadAsStreamAsync(token))
                await using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, true))
                {
                    var lastUpdate = Stopwatch.StartNew();
                    await DownloadHttpClient.CopyBodyAsync(input, output, expectedBytes, written =>
                    {
                        if (total > 0 && (lastUpdate.ElapsedMilliseconds >= 100 || written == total))
                        {
                            UpdateHUDProgress((double)written / total, written, total);
                            lastUpdate.Restart();
                        }
                    }, TimeSpan.FromSeconds(30), token);
                    await output.FlushAsync(token);
                }
                return await CommitDownloadAsync(temporary, destination, token);
            }
            finally { DownloadFile.Cleanup(temporary); }
        }

        private async Task<string> PerformBlobDownloadAsync(CoreWebView2 core, string url, string destination, CancellationToken token)
        {
            var request = new BlobRequest { Url = url, TemporaryPath = DownloadFile.TemporaryPath(destination) };
            pendingBlob = request;
            ShowHUDIndeterminate("正在提取视频流...", Path.GetFileName(destination));
            try
            {
                // JSON encoding also handles apostrophes, backslashes, and line breaks.
                await core.ExecuteScriptAsync($"window.tokmacDownloadBlob({JsonSerializer.Serialize(url)});").WaitAsync(token);
                await request.Started.Task.WaitAsync(TimeSpan.FromSeconds(15), token);
                await request.Completed.Task.WaitAsync(token);
                return await CommitDownloadAsync(request.TemporaryPath, destination, token);
            }
            finally
            {
                try
                {
                    if (request.Operation is { } operation)
                    {
                        if (operation.State == CoreWebView2DownloadState.InProgress)
                        {
                            operation.Cancel();
                            try { await request.Completed.Task.WaitAsync(TimeSpan.FromSeconds(5)); }
                            catch (Exception) when (token.IsCancellationRequested) { }
                        }
                        operation.BytesReceivedChanged -= request.ProgressHandler;
                        operation.StateChanged -= request.StateHandler;
                    }
                }
                catch (Exception error) when (token.IsCancellationRequested && error is COMException or InvalidOperationException)
                {
                    // The browser may already have released this native download.
                }
                finally
                {
                    if (pendingBlob == request) pendingBlob = null;
                    DownloadFile.Cleanup(request.TemporaryPath);
                }
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
            if (isFullScreen) ToggleFullScreen();
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

        private async void BtnReload_Click(object sender, RoutedEventArgs e)
        {
            await RecoverBrowserAsync();
        }

        internal void ToggleFullScreen()
        {
            if (!isFullScreen)
            {
                savedWindowState = WindowState;
                savedWindowStyle = WindowStyle;
                savedResizeMode = ResizeMode;
                savedBounds = WindowState == WindowState.Normal ? new Rect(Left, Top, Width, Height) : RestoreBounds;
                savedToolbarHeight = toolbarRow.Height;
                WindowState = WindowState.Normal;
                WindowStyle = WindowStyle.None;
                ResizeMode = ResizeMode.NoResize;
                toolbarBar.Visibility = Visibility.Collapsed;
                toolbarRow.Height = new GridLength(0);
                WindowState = WindowState.Maximized;
                isFullScreen = true;
            }
            else
            {
                WindowState = WindowState.Normal;
                WindowStyle = savedWindowStyle;
                ResizeMode = savedResizeMode;
                if (!savedBounds.IsEmpty)
                {
                    Left = savedBounds.Left;
                    Top = savedBounds.Top;
                    Width = savedBounds.Width;
                    Height = savedBounds.Height;
                }
                toolbarBar.Visibility = Visibility.Visible;
                toolbarRow.Height = savedToolbarHeight;
                WindowState = savedWindowState;
                isFullScreen = false;
            }
        }

        private async void MainWindow_KeyDown(object sender, KeyEventArgs e)
        {
            if (Keyboard.Modifiers == (ModifierKeys.Control | ModifierKeys.Shift))
            {
                if (e.Key == Key.D)
                {
                    e.Handled = true;
                    await ShowWatchLaterAsync();
                }
                else if (e.Key == Key.L)
                {
                    e.Handled = true;
                    await CopyCurrentVideoLinkAsync();
                }
                return;
            }
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
                else if (e.Key == Key.D)
                {
                    e.Handled = true;
                    await SaveCurrentVideoAsync();
                }
            }
            else if (e.Key == Key.F5)
            {
                e.Handled = true;
                BtnReload_Click(sender, e);
            }
            else if (e.Key == Key.Escape && isFullScreen)
            {
                e.Handled = true;
                ToggleFullScreen();
            }
            else if (e.Key == Key.F11)
            {
                e.Handled = true;
                ToggleFullScreen();
            }
        }
    }
}
