using AELanguageSwitcher.Core;

namespace AELanguageSwitcher.Core.Tests;

[TestClass]
public sealed class LanguageDetectionTests
{
    [DataTestMethod]
    [DataRow(true, "zh-CN", true, EffectiveLanguage.English, ChineseEligibility.Available)]
    [DataRow(false, "zh-CN", true, EffectiveLanguage.SimplifiedChinese, ChineseEligibility.Available)]
    [DataRow(false, "en-US", true, EffectiveLanguage.SystemDefault, ChineseEligibility.SystemLanguageNotSimplifiedChinese)]
    [DataRow(false, "zh-CN", false, EffectiveLanguage.SystemDefault, ChineseEligibility.MissingResource)]
    public void DetectDerivesLanguageState(
        bool markerExists,
        string preferredLanguage,
        bool hasChinese,
        EffectiveLanguage expectedLanguage,
        ChineseEligibility expectedEligibility)
    {
        var locales = hasChinese
            ? new HashSet<AELocale> { AELocale.SimplifiedChinese, AELocale.EnglishUS }
            : new HashSet<AELocale> { AELocale.EnglishUS };
        var installation = new AEInstallation("AE", "26.0", @"C:\AE\AfterFX.exe", locales);
        var detector = new LanguageStateDetector(new LanguageEnvironmentFake(markerExists, preferredLanguage));

        var state = detector.Detect(installation);

        Assert.AreEqual(expectedLanguage, state.Effective);
        Assert.AreEqual(expectedEligibility, state.ChineseEligibility);
    }

    [DataTestMethod]
    [DataRow("zh-CN", true)]
    [DataRow("zh-Hans", true)]
    [DataRow("zh-Hans-CN", true)]
    [DataRow("zh_CN", true)]
    [DataRow("zh-TW", false)]
    [DataRow("zh-Hant", false)]
    public void SimplifiedChineseRecognitionIsExplicit(string language, bool expected)
    {
        Assert.AreEqual(expected, LanguageStateDetector.IsSimplifiedChinese(language));
    }
}

internal sealed class LanguageEnvironmentFake(bool markerExists, params string[] languages) : ILanguageEnvironment
{
    public bool MarkerExists => markerExists;
    public IReadOnlyList<string> PreferredLanguages => languages;
}

