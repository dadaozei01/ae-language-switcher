using System.Globalization;

namespace AELanguageSwitcher.Core;

public interface ILanguageStateDetector
{
    LanguageState Detect(AEInstallation installation);
}

public interface ILanguageEnvironment
{
    bool MarkerExists { get; }
    IReadOnlyList<string> PreferredLanguages { get; }
}

public sealed class LanguageStateDetector(ILanguageEnvironment environment) : ILanguageStateDetector
{
    public LanguageState Detect(AEInstallation installation)
    {
        var preferredLanguage = environment.PreferredLanguages.FirstOrDefault() ?? "en-US";
        var eligibility = GetEligibility(installation, preferredLanguage);
        var effective = environment.MarkerExists
            ? EffectiveLanguage.English
            : eligibility == ChineseEligibility.Available
                ? EffectiveLanguage.SimplifiedChinese
                : EffectiveLanguage.SystemDefault;

        return new LanguageState(effective, eligibility, environment.MarkerExists, preferredLanguage);
    }

    public static bool IsSimplifiedChinese(string language) =>
        language.Equals("zh-CN", StringComparison.OrdinalIgnoreCase)
        || language.Equals("zh_CN", StringComparison.OrdinalIgnoreCase)
        || language.StartsWith("zh-Hans", StringComparison.OrdinalIgnoreCase);

    private static ChineseEligibility GetEligibility(AEInstallation installation, string preferredLanguage)
    {
        if (!installation.AvailableLocales.Contains(AELocale.SimplifiedChinese))
        {
            return ChineseEligibility.MissingResource;
        }
        return IsSimplifiedChinese(preferredLanguage)
            ? ChineseEligibility.Available
            : ChineseEligibility.SystemLanguageNotSimplifiedChinese;
    }
}

public sealed class WindowsLanguageEnvironment(string markerPath) : ILanguageEnvironment
{
    public bool MarkerExists => File.Exists(markerPath) || Directory.Exists(markerPath);

    public IReadOnlyList<string> PreferredLanguages => new[]
        {
            CultureInfo.CurrentUICulture.Name,
            CultureInfo.InstalledUICulture.Name
        }
        .Where(language => !string.IsNullOrWhiteSpace(language))
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .ToArray();
}

