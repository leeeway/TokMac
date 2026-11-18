using System;
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
        }
        finally { window.Close(); app.Shutdown(); }
    }
}
