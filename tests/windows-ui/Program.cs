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
        var video = SavedVideo.Parse("https://www.tiktok.com/@current/video/123")!;
        store.Add(video);
        var dialog = new WatchLaterWindow(store);
        try
        {
            var remove = (Button)dialog.FindName("removeButton");
            var open = (Button)dialog.FindName("openButton");
            if (!remove.IsEnabled || !open.IsEnabled || dialog.SelectedVideo?.Url != video.Url)
                throw new Exception("A saved video must be selected and available to open or remove");
            remove.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            if (remove.IsEnabled || open.IsEnabled || dialog.SelectedVideo != null || store.Videos().Count != 0)
                throw new Exception("Removing the last video must persist and leave an empty list");
        }
        finally
        {
            dialog.Close();
            Directory.Delete(directory, recursive: true);
        }
    }
}
