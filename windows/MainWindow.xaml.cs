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
        private string? pendingBlobDestinationPath;
        private DispatcherTimer? autoDismissTimer;
        private CancellationTokenSource? downloadCts;

        public MainWindow()
        {
            InitializeComponent();
            Loaded += MainWindow_Loaded;
            KeyDown += MainWindow_KeyDown;
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

                // Clean Mode CSS injection
                await webView.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(@"
                    (function() {
                        const style = document.createElement('style');
                        style.textContent = `
                            /* Hide distracting app promotion prompts */
                            div[class*='DivBannerContainer'],
                            div[class*='DivDownloadLinkContainer'],
                            div[class*='DivMobileAppWrapper'],
                            div[class*='DivGetAppContainer'],
                            div[class*='DivDesktopDownloadPrompt'],
                            div[id*='get-app'],
                            div[class*='DivAppBannerContainer'],
                            div[class*='DivTopNavDownloadLink'] {
                                display: none !important;
                            }
                        `;
                        document.head.appendChild(style);

                        // Unlock right click
                        window.addEventListener('contextmenu', function(e) {
                            e.stopImmediatePropagation();
                        }, true);

                        // Video Finder & Extractor
                        window.tokmacGetVideoDownloadInfo = function() {
                            const videos = Array.from(document.querySelectorAll('video'));
                            if (!videos.length) return null;
                            const centerY = window.innerHeight / 2;
                            let bestVideo = videos[0];
                            let minDistance = 999999;
                            for (const v of videos) {
                                const rect = v.getBoundingClientRect();
                                const dist = Math.abs((rect.top + rect.bottom) / 2 - centerY);
                                if (dist < minDistance) {
                                    minDistance = dist;
                                    bestVideo = v;
                                }
                            }

                            let downloadUrl = null;
                            let src = bestVideo.currentSrc || bestVideo.src;
                            if (src && src.startsWith('http')) downloadUrl = src;

                            if (!downloadUrl) {
                                const sources = bestVideo.querySelectorAll('source');
                                for (const s of sources) {
                                    if (s.src && s.src.startsWith('http')) {
                                        downloadUrl = s.src;
                                        break;
                                    }
                                }
                            }

                            if (!downloadUrl) {
                                try {
                                    const uData = window.__UNIVERSAL_DATA_FOR_REHYDRATION__;
                                    if (uData) {
                                        function search(obj) {
                                            if (!obj || downloadUrl) return;
                                            if (typeof obj === 'object') {
                                                if (obj.downloadAddr) downloadUrl = obj.downloadAddr;
                                                else if (obj.playAddr) downloadUrl = obj.playAddr;
                                                if (!downloadUrl) {
                                                    for (const k in obj) search(obj[k]);
                                                }
                                            }
                                        }
                                        search(uData);
                                    }
                                } catch(e) {}
                            }

                            if (!downloadUrl && src && src.startsWith('blob:')) {
                                downloadUrl = src;
                            }

                            const authorEl = document.querySelector('h3[data-e2e=""browse-user-title""]') ||
                                             document.querySelector('span[data-e2e=""browse-user-title""]') ||
                                             document.querySelector('span[data-e2e=""user-title""]') ||
                                             document.querySelector('a[data-e2e=""video-author-uniqueid""]');
                            const author = authorEl ? authorEl.innerText.trim() : 'TikTok';

                            return {
                                url: downloadUrl,
                                author: author,
                                isBlob: downloadUrl ? downloadUrl.startsWith('blob:') : false
                            };
                        };

                        window.tokmacDownloadBlob = function(blobUrl) {
                            fetch(blobUrl)
                                .then(r => r.blob())
                                .then(blob => {
                                    const reader = new FileReader();
                                    reader.onloadend = function() {
                                        window.chrome.webview.postMessage({
                                            type: 'saveBase64Video',
                                            base64: reader.result
                                        });
                                    };
                                    reader.readAsDataURL(blob);
                                })
                                .catch(err => {
                                    window.chrome.webview.postMessage({
                                        type: 'blobError',
                                        error: err.message
                                    });
                                });
                        };
                    })();
                ");

                webView.CoreWebView2.WebMessageReceived += CoreWebView2_WebMessageReceived;
                webView.CoreWebView2.Navigate("https://www.tiktok.com/");
            }
            catch (Exception ex)
            {
                MessageBox.Show($"WebView2 初始化失败: {ex.Message}\n请确保已安装 Microsoft Edge WebView2 运行时。", "TokMac 错误", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private async void CoreWebView2_WebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            try
            {
                using var doc = JsonDocument.Parse(e.WebMessageAsJson);
                var root = doc.RootElement;
                if (root.TryGetProperty("type", out var typeProp))
                {
                    string type = typeProp.GetString() ?? "";
                    if (type == "saveBase64Video" && root.TryGetProperty("base64", out var base64Prop))
                    {
                        string base64 = base64Prop.GetString() ?? "";
                        if (!string.IsNullOrEmpty(pendingBlobDestinationPath))
                        {
                            await SaveBase64ToFileAsync(base64, pendingBlobDestinationPath);
                            pendingBlobDestinationPath = null;
                        }
                    }
                    else if (type == "blobError" && root.TryGetProperty("error", out var errProp))
                    {
                        ShowHUDError("提取视频流失败: " + errProp.GetString());
                    }
                }
            }
            catch (Exception ex)
            {
                ShowHUDError("解析视频数据失败: " + ex.Message);
            }
        }

        // MARK: - Actions
        private async void BtnDownload_Click(object sender, RoutedEventArgs e)
        {
            await TriggerVideoDownloadAsync();
        }

        private async Task TriggerVideoDownloadAsync()
        {
            if (webView.CoreWebView2 == null) return;

            try
            {
                string jsonResult = await webView.CoreWebView2.ExecuteScriptAsync("window.tokmacGetVideoDownloadInfo && window.tokmacGetVideoDownloadInfo();");
                if (string.IsNullOrEmpty(jsonResult) || jsonResult == "null")
                {
                    ShowHUDError("未检测到当前播放的视频，请等待加载后重试");
                    return;
                }

                using var doc = JsonDocument.Parse(jsonResult);
                var root = doc.RootElement;
                string? url = root.TryGetProperty("url", out var urlProp) ? urlProp.GetString() : null;
                string author = root.TryGetProperty("author", out var authProp) ? (authProp.GetString() ?? "TikTok") : "TikTok";
                bool isBlob = root.TryGetProperty("isBlob", out var blobProp) && blobProp.GetBoolean();

                if (string.IsNullOrEmpty(url))
                {
                    ShowHUDError("未找到视频源地址，请开始播放后重试");
                    return;
                }

                // Clean author name for filesystem
                foreach (char c in Path.GetInvalidFileNameChars())
                {
                    author = author.Replace(c, '_');
                }

                long timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                string suggestedFilename = $"{author}_{timestamp}.mp4";

                var saveDialog = new SaveFileDialog
                {
                    Title = "选择保存视频的位置",
                    Filter = "MP4 视频 (*.mp4)|*.mp4|所有文件 (*.*)|*.*",
                    FileName = suggestedFilename,
                    InitialDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads")
                };

                if (saveDialog.ShowDialog(this) == true)
                {
                    string savePath = saveDialog.FileName;

                    if (isBlob)
                    {
                        pendingBlobDestinationPath = savePath;
                        ShowHUDIndeterminate("正在提取视频流...", Path.GetFileName(savePath));
                        await webView.CoreWebView2.ExecuteScriptAsync($"window.tokmacDownloadBlob && window.tokmacDownloadBlob('{url}');");
                    }
                    else
                    {
                        await PerformDirectDownloadAsync(url, savePath);
                    }
                }
            }
            catch (Exception ex)
            {
                ShowHUDError("下载出现错误: " + ex.Message);
            }
        }

        private async Task PerformDirectDownloadAsync(string url, string destinationPath)
        {
            downloadCts?.Cancel();
            downloadCts = new CancellationTokenSource();
            var token = downloadCts.Token;

            ShowHUDStart(Path.GetFileName(destinationPath));

            try
            {
                using var client = new HttpClient();
                client.DefaultRequestHeaders.Add("Referer", "https://www.tiktok.com/");
                client.DefaultRequestHeaders.Add("User-Agent", webView.CoreWebView2.Settings.UserAgent);

                using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, token);
                response.EnsureSuccessStatusCode();

                long? totalBytes = response.Content.Headers.ContentLength;
                using var contentStream = await response.Content.ReadAsStreamAsync(token);
                using var fileStream = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None, 8192, true);

                var buffer = new byte[8192];
                long totalRead = 0;
                int bytesRead;

                while ((bytesRead = await contentStream.ReadAsync(buffer, 0, buffer.Length, token)) > 0)
                {
                    await fileStream.WriteAsync(buffer, 0, bytesRead, token);
                    totalRead += bytesRead;

                    if (totalBytes.HasValue && totalBytes.Value > 0)
                    {
                        double progress = (double)totalRead / totalBytes.Value;
                        UpdateHUDProgress(progress, totalRead, totalBytes.Value);
                    }
                }

                FinishHUD(destinationPath);
            }
            catch (OperationCanceledException)
            {
                HideHUD();
            }
            catch (Exception ex)
            {
                ShowHUDError("下载失败: " + ex.Message);
            }
        }

        private async Task SaveBase64ToFileAsync(string base64, string destinationPath)
        {
            try
            {
                if (base64.Contains(","))
                {
                    base64 = base64.Substring(base64.IndexOf(",") + 1);
                }

                byte[] bytes = Convert.FromBase64String(base64);
                await File.WriteAllBytesAsync(destinationPath, bytes);
                FinishHUD(destinationPath);
            }
            catch (Exception ex)
            {
                ShowHUDError("写入文件失败: " + ex.Message);
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
            taskbarInfo.ProgressState = TaskbarItemProgressState.Normal;
            taskbarInfo.ProgressValue = 0;
        }

        private void UpdateHUDProgress(double fraction, long writtenBytes, long totalBytes)
        {
            int percent = (int)(fraction * 100);
            hudTitle.Text = $"正在下载视频 ({percent}%)";
            hudSubtitle.Text = $"{FormatBytes(writtenBytes)} / {FormatBytes(totalBytes)}";
            hudProgressBar.Value = percent;

            taskbarInfo.ProgressValue = fraction;
        }

        private void ShowHUDIndeterminate(string title, string subtitle)
        {
            autoDismissTimer?.Stop();
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
            downloadCts?.Cancel();
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
