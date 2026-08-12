using System.Windows;
using AELanguageSwitcher.Core;

namespace AELanguageSwitcher.App;

public partial class MainWindow : Window
{
    private bool _hasLoaded;

    public MainWindow() => InitializeComponent();

    private void Window_Loaded(object sender, RoutedEventArgs e)
    {
        _hasLoaded = true;
        RefreshIfReady();
    }

    private void Window_Activated(object? sender, EventArgs e)
    {
        if (_hasLoaded)
        {
            RefreshIfReady();
        }
    }

    private void RefreshIfReady()
    {
        if (DataContext is MainViewModel { IsBusy: false } viewModel)
        {
            viewModel.Refresh();
        }
    }
}
