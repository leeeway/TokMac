using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Web.WebView2.Wpf;
using TokMac;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        var app = new App();
        app.InitializeComponent();
        var window = new MainWindow { Left = 50, Top = 60, Width = 1080, Height = 760 };
        try
        {
            var style = window.WindowStyle;
            var resizeMode = window.ResizeMode;
            window.ToggleFullScreen();
            if (window.WindowStyle != WindowStyle.None || window.WindowState != WindowState.Maximized ||
                ((FrameworkElement)window.FindName("toolbarBar")).Visibility != Visibility.Collapsed ||
                ((RowDefinition)window.FindName("toolbarRow")).Height.Value != 0)
                throw new Exception("Full screen must remove window chrome and toolbar");
            window.ToggleFullScreen();
            if (window.WindowStyle != style || window.ResizeMode != resizeMode || window.WindowState != WindowState.Normal ||
                window.Left != 50 || window.Top != 60 || window.Width != 1080 || window.Height != 760 ||
                ((FrameworkElement)window.FindName("toolbarBar")).Visibility != Visibility.Visible)
                throw new Exception("Leaving full screen must restore window bounds and chrome");
            window.WindowState = WindowState.Maximized;
            window.ToggleFullScreen();
            window.ToggleFullScreen();
            if (window.WindowState != WindowState.Maximized) throw new Exception("Original maximized state must be restored");

            var host = (Grid)window.FindName("webHost");
            var oldBrowser = host.Children[0];
            var overlay = window.FindName("browserStatus");
            window.ReplaceBrowserControl();
            if (host.Children[0] is not WebView2CompositionControl || host.Children[0] == oldBrowser ||
                host.Children.Contains(oldBrowser) || host.Children[^1] != overlay)
                throw new Exception("Browser recovery must attach a new control below the recovery overlay");

            CheckWatchLaterDialog();
        }
        finally { window.Close(); app.Shutdown(); }
    }

    private static void CheckWatchLaterDialog()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var store = new WatchLaterStore(Path.Combine(directory, "watch-later.json"));
        var png = File.ReadAllBytes("windows/Resources/app.png");
        var thumbnail = WatchLaterThumbnails.MakeJpeg(png);
        if (WatchLaterThumbnails.ReadThumbnail(thumbnail) is not { PixelWidth: 64, PixelHeight: 64 } ||
            WatchLaterThumbnails.MakeJpeg("not an image"u8.ToArray()) != null ||
            WatchLaterThumbnails.AllowedUrl("https://tiktokcdn.com.invalid/cover.jpg") != null ||
            WatchLaterThumbnails.AllowedUrl("https://img.tiktokcdn-us.com/cover.jpg") == null)
            throw new Exception("Thumbnails must be validated and converted into a local JPEG");
        var legacy = SavedVideo.Parse("https://www.tiktok.com/@legacy/video/456")!;
        var video = SavedVideo.Parse("https://www.tiktok.com/@current/video/123", "Sunset over Shanghai", thumbnail)!;
        store.Add(legacy);
        store.Add(video);
        var dialog = new WatchLaterWindow(store);
        try
        {
            var remove = (Button)dialog.FindName("removeButton");
            var open = (Button)dialog.FindName("openButton");
            if (!remove.IsEnabled || !open.IsEnabled || dialog.SelectedVideo?.Url != video.Url)
                throw new Exception("A saved video must be selected and available to open or remove");
            var search = (TextBox)dialog.FindName("search");
            search.Text = "missing";
            if (open.IsEnabled || remove.IsEnabled || dialog.SelectedVideo != null)
                throw new Exception("An empty search must disable item actions");
            search.Text = "SHANGHAI current";
            if (dialog.SelectedVideo?.Id != video.Id)
                throw new Exception("Search must filter titles and authors");
            remove.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            if (remove.IsEnabled || open.IsEnabled || dialog.SelectedVideo != null || store.Videos().Count != 1)
                throw new Exception("Removing a filtered video must preserve hidden matches");
            search.Text = "456";
            if (dialog.SelectedVideo?.Id != legacy.Id)
                throw new Exception("Old bookmarks must remain available by video ID");
        }
        finally
        {
            dialog.Close();
            Directory.Delete(directory, recursive: true);
        }
    }
}
