using System.Text;
using AELanguageSwitcher.Core;

namespace AELanguageSwitcher.Core.Tests;

[TestClass]
public sealed class VersionLanguagePreferencesTests
{
    private sealed class HistoryFake(string? language) : IProductLanguageHistory
    {
        public string? GetLatest(string productVersion) => language;
    }

    [DataTestMethod]
    [DataRow("25.3.0x5", "25.3")]
    [DataRow("24.6.2", "24.6")]
    public void LocatorUsesMajorMinorPreferenceFolder(string version, string folder)
    {
        var installation = new AEInstallation("AE", version, @"C:\AE\AfterFX.exe", new HashSet<AELocale>());
        var path = new VersionLanguagePreferenceLocator(@"C:\Prefs").GetDatabasePath(installation);
        Assert.AreEqual(Path.Combine(@"C:\Prefs", folder, "Debug Database.txt"), path);
    }

    [DataTestMethod]
    [DataRow("en_US", EffectiveLanguage.English)]
    [DataRow("zh_CN", EffectiveLanguage.SimplifiedChinese)]
    [DataRow("", EffectiveLanguage.Unknown)]
    [DataRow("fr_FR", EffectiveLanguage.Unknown)]
    public void ParserReadsApplicationLanguage(string value, EffectiveLanguage expected)
    {
        var bytes = Encoding.UTF8.GetBytes($"ApplicationLanguage\t{value}\t\r\nOtherKey\ttrue\tfalse\r\n");
        var parsed = DebugDatabaseParser.Parse(bytes);
        Assert.AreEqual(expected, parsed.Effective);
        Assert.AreEqual(value, parsed.Language);
        Assert.AreEqual("\r\n", parsed.Format.NewLine);
    }

    [TestMethod]
    public void ParserPreservesUtf8Bom()
    {
        var body = Encoding.UTF8.GetBytes("ApplicationLanguage\tzh_CN\t\n");
        var bytes = Encoding.UTF8.GetPreamble().Concat(body).ToArray();
        Assert.IsTrue(DebugDatabaseParser.Parse(bytes).Format.HasBom);
    }

    [DataTestMethod]
    [DataRow("OtherKey\ttrue\tfalse\r\n")]
    [DataRow("ApplicationLanguage\ten_US\t\r\nApplicationLanguage\tzh_CN\t\r\n")]
    [DataRow("ApplicationLanguage\ten_US\r\n")]
    public void ParserRejectsMissingDuplicateOrMalformedRows(string text)
    {
        Assert.ThrowsException<PreferenceFormatException>(() =>
            DebugDatabaseParser.Parse(Encoding.UTF8.GetBytes(text)));
    }

    [TestMethod]
    public void DetectorUsesBlankDatabaseValueFallback()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        var folder = Path.Combine(root, "25.3");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "Debug Database.txt"), "ApplicationLanguage\t\t\r\n");
        try
        {
            var installation = new AEInstallation("AE", "25.3.1", @"C:\AE\AfterFX.exe", new HashSet<AELocale>());
            var state = new VersionLanguageDetector(new VersionLanguagePreferenceLocator(root), new HistoryFake("zh_CN")).Detect(installation);
            Assert.AreEqual(EffectiveLanguage.SimplifiedChinese, state.Effective);
            Assert.IsTrue(state.IsFallback);
        }
        finally { Directory.Delete(root, true); }
    }
}
