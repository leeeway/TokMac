using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Windows;
using System.Windows.Controls;

namespace TokMac;

public partial class WatchLaterWindow : Window
{
    private readonly WatchLaterStore store;
    private IReadOnlyList<SavedVideo>? entries;
    internal SavedVideo? SelectedVideo => videos.SelectedItem as SavedVideo;

    internal WatchLaterWindow(WatchLaterStore store)
    {
        this.store = store;
        InitializeComponent();
        search.TextChanged += (_, _) => ApplySearch();
        Loaded += (_, _) => search.Focus();
        Reload();
    }

    internal void Reload()
    {
        try { entries = store.Videos(); }
        catch (Exception error)
        {
            Debug.WriteLine(error);
            entries = null;
        }
        ApplySearch();
    }

    private void ApplySearch()
    {
        if (entries == null)
        {
            videos.ItemsSource = null;
            ShowStatus("无法读取稍后看列表");
            return;
        }
        var selected = SelectedVideo?.Id;
        var matches = entries.Where(video => video.Matches(search.Text)).ToList();
        videos.ItemsSource = matches;
        if (matches.Count > 0)
        {
            videos.SelectedIndex = Math.Max(0, matches.FindIndex(video => video.Id == selected));
            videos.ScrollIntoView(videos.SelectedItem);
        }
        ShowStatus(entries.Count == 0 ? "还没有收藏的视频" : matches.Count == 0 ? "没有匹配的视频" : null);
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
        Reload();
    }
}
