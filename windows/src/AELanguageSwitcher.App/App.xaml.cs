using System.IO;
using System.Windows;
using AELanguageSwitcher.Core;

namespace AELanguageSwitcher.App;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        if (string.IsNullOrWhiteSpace(documents))
        {
            MessageBox.Show("无法定位当前用户的“文档”文件夹。", "启动失败", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
            return;
        }

        var markerPath = Path.Combine(documents, "ae_force_english.txt");
        var scanner = new InstallationScanner(
            new WindowsInstallationSource(),
            new FileExecutableMetadata(),
            new WindowsResourceProbe());
        var preferencesRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Adobe", "After Effects");
        var ccxRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Adobe", "CCX Welcome");
        var locator = new VersionLanguagePreferenceLocator(preferencesRoot);
        var viewModel = new MainViewModel(
            scanner,
            new VersionLanguageDetector(locator, new CcxProductLanguageHistory(ccxRoot)),
            new AfterEffectsProcessMonitor(new WindowsProcessSnapshot()),
            new VersionLanguageSwitcher(locator, new LegacyMarkerMigrator(markerPath)),
            new WpfUserDialog());

        MainWindow = new MainWindow { DataContext = viewModel };
        MainWindow.Show();
    }
}
