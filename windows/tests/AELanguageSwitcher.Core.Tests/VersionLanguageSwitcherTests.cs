using System.Text;
using AELanguageSwitcher.Core;

namespace AELanguageSwitcher.Core.Tests;

[TestClass]
public sealed class VersionLanguageSwitcherTests
{
    [TestMethod]
    public void SwitchChangesOnlySelectedVersionAndMigratesEmptyMarker()
    {
        var root = Path.Combine(Path.GetTempPath(), $"ae-version-{Guid.NewGuid():N}");
        var preferences = Path.Combine(root, "prefs");
        var selectedFolder = Path.Combine(preferences, "25.3");
        var otherFolder = Path.Combine(preferences, "24.6");
        Directory.CreateDirectory(selectedFolder);
        Directory.CreateDirectory(otherFolder);
        var selected = Path.Combine(selectedFolder, "Debug Database.txt");
        var other = Path.Combine(otherFolder, "Debug Database.txt");
        File.WriteAllText(selected, "ApplicationLanguage\ten_US\t\r\nOtherKey\ttrue\tfalse\r\n", new UTF8Encoding(true));
        File.WriteAllText(other, "ApplicationLanguage\ten_US\t\r\n");
        var marker = Path.Combine(root, "ae_force_english.txt");
        using (File.Create(marker)) { }
        try
        {
            var installation = new AEInstallation("AE 2025", "25.3", @"C:\AE2025\AfterFX.exe",
                new HashSet<AELocale> { AELocale.EnglishUS, AELocale.SimplifiedChinese });
            var locator = new VersionLanguagePreferenceLocator(preferences);
            var result = new VersionLanguageSwitcher(locator, new LegacyMarkerMigrator(marker))
                .Switch(installation, TargetLanguage.SimplifiedChinese);

            Assert.AreEqual(EffectiveLanguage.SimplifiedChinese, result.Effective);
            StringAssert.Contains(File.ReadAllText(selected), "ApplicationLanguage\tzh_CN\t");
            StringAssert.Contains(File.ReadAllText(selected), "OtherKey\ttrue\tfalse");
            StringAssert.Contains(File.ReadAllText(other), "ApplicationLanguage\ten_US\t");
            Assert.IsFalse(File.Exists(marker));
            Assert.AreEqual(1, Directory.GetFiles(selectedFolder, "Debug Database.txt.*.bak").Length);
            Assert.AreEqual(1, Directory.GetFiles(root, ".ae-language-switcher-*.quarantine").Length);
        }
        finally { Directory.Delete(root, true); }
    }

    [TestMethod]
    public void NonEmptyLegacyMarkerBlocksBeforePreferenceMutation()
    {
        var root = Path.Combine(Path.GetTempPath(), $"ae-version-{Guid.NewGuid():N}");
        var folder = Path.Combine(root, "prefs", "25.3");
        Directory.CreateDirectory(folder);
        var database = Path.Combine(folder, "Debug Database.txt");
        File.WriteAllText(database, "ApplicationLanguage\ten_US\t\r\n");
        var marker = Path.Combine(root, "ae_force_english.txt");
        File.WriteAllText(marker, "keep");
        try
        {
            var install = new AEInstallation("AE", "25.3", @"C:\AE\AfterFX.exe", new HashSet<AELocale>());
            Assert.ThrowsException<LanguageSwitchException>(() =>
                new VersionLanguageSwitcher(new VersionLanguagePreferenceLocator(Path.Combine(root, "prefs")), new LegacyMarkerMigrator(marker))
                    .Switch(install, TargetLanguage.SimplifiedChinese));
            StringAssert.Contains(File.ReadAllText(database), "ApplicationLanguage\ten_US\t");
        }
        finally { Directory.Delete(root, true); }
    }
}
