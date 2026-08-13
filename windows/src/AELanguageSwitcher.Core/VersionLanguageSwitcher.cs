using System.Text;

namespace AELanguageSwitcher.Core;

public interface IVersionLanguageSwitcher
{
    VersionLanguageState Switch(AEInstallation installation, TargetLanguage target);
}

public sealed class VersionLanguageSwitcher(
    VersionLanguagePreferenceLocator locator,
    LegacyMarkerMigrator markerMigrator) : IVersionLanguageSwitcher
{
    public VersionLanguageState Switch(AEInstallation installation, TargetLanguage target)
    {
        var path = locator.GetDatabasePath(installation);
        if (!File.Exists(path))
            throw new LanguageSwitchException(LanguageSwitchErrorCode.FileOperation, "该版本尚未生成 Debug Database.txt，请先正常启动并退出一次。");

        var original = File.ReadAllBytes(path);
        var parsed = DebugDatabaseParser.Parse(original);
        var language = target == TargetLanguage.English ? "en_US" : "zh_CN";
        if (target == TargetLanguage.English && !installation.AvailableLocales.Contains(AELocale.EnglishUS))
            throw new LanguageSwitchException(LanguageSwitchErrorCode.ChineseUnavailable, "所选版本缺少 English 资源。");
        if (target == TargetLanguage.SimplifiedChinese && !installation.AvailableLocales.Contains(AELocale.SimplifiedChinese))
            throw new LanguageSwitchException(LanguageSwitchErrorCode.ChineseUnavailable, "所选版本缺少简体中文资源。");

        using var marker = markerMigrator.Prepare();
        var columns = parsed.Lines[parsed.LanguageLineIndex].Split('\t');
        columns[1] = language;
        var lines = parsed.Lines.ToArray();
        lines[parsed.LanguageLineIndex] = string.Join('\t', columns);
        var text = string.Join(parsed.Format.NewLine, lines);
        var body = new UTF8Encoding(false).GetBytes(text);
        var replacement = parsed.Format.HasBom ? Encoding.UTF8.Preamble.ToArray().Concat(body).ToArray() : body;
        var suffix = $"{DateTime.UtcNow:yyyyMMddHHmmssfff}.{Guid.NewGuid():N}";
        var backup = $"{path}.{suffix}.bak";
        var temp = $"{path}.{suffix}.tmp";
        File.Copy(path, backup, false);
        try
        {
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                stream.Write(replacement);
                stream.Flush(true);
            }
            File.Replace(temp, path, null);
            var verified = DebugDatabaseParser.Parse(File.ReadAllBytes(path));
            if (verified.Language != language) throw new IOException("语言写入验证失败。");
            marker.Commit();
            return new VersionLanguageState(verified.Effective, verified.Language, path, false);
        }
        catch
        {
            if (File.Exists(backup)) File.Copy(backup, path, true);
            throw;
        }
        finally
        {
            if (File.Exists(temp)) File.Delete(temp);
        }
    }
}
