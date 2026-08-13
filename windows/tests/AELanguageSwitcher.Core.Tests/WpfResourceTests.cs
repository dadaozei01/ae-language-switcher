using System.Runtime.CompilerServices;

namespace AELanguageSwitcher.Core.Tests;

[TestClass]
public sealed class WpfResourceTests
{
    [TestMethod]
    public void MainWindowDoesNotReferenceUndefinedInverseConverter()
    {
        var xaml = File.ReadAllText(GetMainWindowPath());
        Assert.IsFalse(xaml.Contains("InverseBooleanConverter", StringComparison.Ordinal));
    }

    private static string GetMainWindowPath([CallerFilePath] string source = "") =>
        Path.GetFullPath(Path.Combine(Path.GetDirectoryName(source)!, "..", "..", "src", "AELanguageSwitcher.App", "MainWindow.xaml"));
}
