using AELanguageSwitcher.Core;

namespace AELanguageSwitcher.Core.Tests;

[TestClass]
public sealed class InstallationScannerTests
{
    [TestMethod]
    public void ScanDeduplicatesFiltersAndSortsCandidates()
    {
        var source = new CandidateSourceFake(
            @"C:\Adobe\Adobe After Effects 25",
            @"C:\Adobe\Adobe After Effects 26",
            @"C:\Adobe\Adobe After Effects Render Engine 27",
            @"C:\Adobe\Adobe After Effects 26");
        var metadata = new ExecutableMetadataFake()
            .Add(@"C:\Adobe\Adobe After Effects 25\Support Files\AfterFX.exe", "After Effects", "25.2")
            .Add(@"C:\Adobe\Adobe After Effects 26\Support Files\AfterFX.exe", "After Effects", "26.0");

        var result = new InstallationScanner(source, metadata, new ResourceProbeFake()).Scan();

        CollectionAssert.AreEqual(new[] { "26.0", "25.2" }, result.Select(item => item.Version).ToArray());
    }

    [TestMethod]
    public void ScanIgnoresMalformedCandidatesAndPopulatesLocales()
    {
        var source = new CandidateSourceFake(@"C:\Adobe\Adobe After Effects 26", @"C:\Adobe\Broken");
        var metadata = new ExecutableMetadataFake()
            .Add(@"C:\Adobe\Adobe After Effects 26\Support Files\AfterFX.exe", "After Effects", "26.0");
        var resources = new ResourceProbeFake(AELocale.EnglishUS, AELocale.SimplifiedChinese);

        var result = new InstallationScanner(source, metadata, resources).Scan();

        Assert.AreEqual(1, result.Count);
        CollectionAssert.AreEquivalent(
            new[] { AELocale.EnglishUS, AELocale.SimplifiedChinese },
            result[0].AvailableLocales.ToArray());
    }
}

internal sealed class CandidateSourceFake(params string[] candidates) : IInstallationSource
{
    public IEnumerable<string> GetCandidates() => candidates;
}

internal sealed class ExecutableMetadataFake : IExecutableMetadata
{
    private readonly Dictionary<string, ExecutableMetadata> _items = new(StringComparer.OrdinalIgnoreCase);

    public ExecutableMetadataFake Add(string path, string name, string version)
    {
        _items[path] = new ExecutableMetadata(name, version);
        return this;
    }

    public ExecutableMetadata? Read(string executablePath) =>
        _items.TryGetValue(executablePath, out var metadata) ? metadata : null;
}

internal sealed class ResourceProbeFake(params AELocale[] locales) : IResourceProbe
{
    public IReadOnlySet<AELocale> Detect(string installationDirectory) => locales.ToHashSet();
}
