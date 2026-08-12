using AELanguageSwitcher.Core;

namespace AELanguageSwitcher.Core.Tests;

[TestClass]
public sealed class DomainTests
{
    [TestMethod]
    public void SemanticVersionsSortNumericallyDescending()
    {
        var versions = new[] { "9.9", "26.0", "25.10", "25.2" };
        Array.Sort(versions, SemanticVersionComparer.Descending);
        CollectionAssert.AreEqual(new[] { "26.0", "25.10", "25.2", "9.9" }, versions);
    }

    [TestMethod]
    public void InstallationIdentityUsesExecutablePath()
    {
        var installation = new AEInstallation(
            "After Effects",
            "26.0",
            @"C:\AE\Support Files\AfterFX.exe",
            new HashSet<AELocale>());

        Assert.AreEqual(@"C:\AE\Support Files\AfterFX.exe", installation.Id);
    }
}

