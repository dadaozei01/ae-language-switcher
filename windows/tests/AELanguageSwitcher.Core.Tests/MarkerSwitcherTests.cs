using AELanguageSwitcher.Core;

namespace AELanguageSwitcher.Core.Tests;

[TestClass]
public sealed class MarkerSwitcherTests
{
    private string _root = null!;
    private string _marker = null!;

    [TestInitialize]
    public void SetUp()
    {
        _root = Path.Combine(Path.GetTempPath(), $"ae-switcher-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_root);
        _marker = Path.Combine(_root, "ae_force_english.txt");
    }

    [TestCleanup]
    public void TearDown()
    {
        if (Directory.Exists(_root))
        {
            Directory.Delete(_root, recursive: true);
        }
    }

    [TestMethod]
    public void EnglishCreatesZeroByteMarkerAndIsIdempotent()
    {
        var switcher = new MarkerSwitcher(_marker);
        switcher.Switch(TargetLanguage.English, ChineseEligibility.Available);
        switcher.Switch(TargetLanguage.English, ChineseEligibility.Available);
        Assert.AreEqual(0, new FileInfo(_marker).Length);
    }

    [TestMethod]
    public void EnglishPreservesExistingNonEmptyFile()
    {
        File.WriteAllText(_marker, "keep me");
        new MarkerSwitcher(_marker).Switch(TargetLanguage.English, ChineseEligibility.Available);
        Assert.AreEqual("keep me", File.ReadAllText(_marker));
    }

    [TestMethod]
    public void DirectoryMarkerIsRejectedWithoutRecursiveDeletion()
    {
        Directory.CreateDirectory(_marker);
        File.WriteAllText(Path.Combine(_marker, "protected.txt"), "protected");

        var error = Assert.ThrowsException<LanguageSwitchException>(() =>
            new MarkerSwitcher(_marker).Switch(TargetLanguage.English, ChineseEligibility.Available));

        Assert.AreEqual(LanguageSwitchErrorCode.UnsafeMarkerType, error.Code);
        Assert.IsTrue(File.Exists(Path.Combine(_marker, "protected.txt")));
    }

    [TestMethod]
    public void ChineseMovesZeroByteMarkerOutOfEffectivePath()
    {
        using (File.Create(_marker)) { }
        new MarkerSwitcher(_marker).Switch(TargetLanguage.SimplifiedChinese, ChineseEligibility.Available);
        Assert.IsFalse(File.Exists(_marker));
        Assert.AreEqual(1, Directory.GetFiles(_root, ".ae-language-switcher-*.quarantine").Length);
    }

    [TestMethod]
    public void ChineseRejectsNonEmptyMarker()
    {
        File.WriteAllText(_marker, "keep me");
        var error = Assert.ThrowsException<LanguageSwitchException>(() =>
            new MarkerSwitcher(_marker).Switch(TargetLanguage.SimplifiedChinese, ChineseEligibility.Available));
        Assert.AreEqual(LanguageSwitchErrorCode.NonEmptyMarker, error.Code);
        Assert.AreEqual("keep me", File.ReadAllText(_marker));
    }

    [TestMethod]
    public void ChineseChecksEligibilityBeforeMutation()
    {
        using (File.Create(_marker)) { }
        var error = Assert.ThrowsException<LanguageSwitchException>(() =>
            new MarkerSwitcher(_marker).Switch(TargetLanguage.SimplifiedChinese, ChineseEligibility.MissingResource));
        Assert.AreEqual(LanguageSwitchErrorCode.ChineseUnavailable, error.Code);
        Assert.IsTrue(File.Exists(_marker));
    }

    [TestMethod]
    public void ChineseRestoresReplacementMovedDuringRace()
    {
        using (File.Create(_marker)) { }
        var switcher = new MarkerSwitcher(_marker, beforeQuarantineMove: () =>
        {
            File.Delete(_marker);
            File.WriteAllText(_marker, "replacement");
        });

        var error = Assert.ThrowsException<LanguageSwitchException>(() =>
            switcher.Switch(TargetLanguage.SimplifiedChinese, ChineseEligibility.Available));

        Assert.AreEqual(LanguageSwitchErrorCode.FileOperation, error.Code);
        Assert.AreEqual("replacement", File.ReadAllText(_marker));
    }
}
