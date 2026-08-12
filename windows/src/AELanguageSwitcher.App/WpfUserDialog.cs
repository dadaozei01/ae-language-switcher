using System.Windows;
using AELanguageSwitcher.Core;

namespace AELanguageSwitcher.App;

public sealed class WpfUserDialog : IUserDialog
{
    public void Show(string title, string message) =>
        MessageBox.Show(message, title, MessageBoxButton.OK, MessageBoxImage.Information);
}
