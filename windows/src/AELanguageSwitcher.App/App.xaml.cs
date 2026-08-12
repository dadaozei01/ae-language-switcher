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
        var languageEnvironment = new WindowsLanguageEnvironment(markerPath);
        var viewModel = new MainViewModel(
            scanner,
            new LanguageStateDetector(languageEnvironment),
            new AfterEffectsProcessMonitor(new WindowsProcessSnapshot()),
            new MarkerSwitcher(markerPath),
            new WpfUserDialog());

        MainWindow = new MainWindow { DataContext = viewModel };
        MainWindow.Show();
    }
}
