using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;

namespace TokMac;

public partial class WatchLaterWindow : Window
{
    private readonly WatchLaterStore store;
    internal SavedVideo? SelectedVideo => videos.SelectedItem as SavedVideo;

    internal WatchLaterWindow(WatchLaterStore store)
    {
        this.store = store;
        InitializeComponent();
        LoadVideos();
    }

    private void LoadVideos(int selectedIndex = 0)
    {
        IReadOnlyList<SavedVideo> entries;
        try { entries = store.Videos(); }
        catch (Exception error)
        {
            Debug.WriteLine(error);
            videos.ItemsSource = null;
            ShowStatus("无法读取稍后看列表");
            return;
        }
        videos.ItemsSource = entries;
        videos.SelectedIndex = Math.Min(selectedIndex, entries.Count - 1);
        ShowStatus(entries.Count == 0 ? "还没有收藏的视频" : null);
    }

    private void ShowStatus(string? message)
    {
        status.Text = message;
        status.Visibility = message == null ? Visibility.Collapsed : Visibility.Visible;
    }

    private void OnSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        openButton.IsEnabled = removeButton.IsEnabled = SelectedVideo != null;
    }

    private void Open_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedVideo != null) DialogResult = true;
    }

    private void Remove_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedVideo is not { } video) return;
        try { store.Remove(video); }
        catch (Exception error)
        {
            Debug.WriteLine(error);
            ShowStatus("无法移除此视频");
            return;
        }
        LoadVideos(videos.SelectedIndex);
    }
}
