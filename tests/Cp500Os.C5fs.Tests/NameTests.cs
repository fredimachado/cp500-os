using System.Text;

namespace Cp500Os.C5fs.Tests;

public class NameTests
{
    [Fact]
    public void Crc16CcittFalseOfTheStandardCheckStringIs0x29B1()
    {
        Assert.Equal(0x29B1, Crc16Ccitt.Compute("123456789"u8));
    }

    [Fact]
    public void FoldingMatchesAccentedCapitals()
    {
        Assert.Equal(FileName.Parse("Ação"), FileName.Parse("AÇÃO"));
        Assert.Equal(FileName.Parse("ÀÉÎÕÜÑ"), FileName.Parse("àéîõüñ"));
        Assert.Equal(FileName.Parse("Readme.TXT").GetHashCode(), FileName.Parse("README.txt").GetHashCode());
    }

    [Fact]
    public void FoldingIsNotAccentStripping()
    {
        Assert.NotEqual(FileName.Parse("Acao"), FileName.Parse("Ação"));
        Assert.NotEqual(FileName.Parse("e"), FileName.Parse("é"));
    }

    [Fact]
    public void MultiplicationAndDivisionSignsDoNotFoldIntoEachOther()
    {
        Assert.NotEqual(FileName.Parse("\u00D7"), FileName.Parse("\u00F7"));
        Assert.NotEqual(FileName.Parse("\u00DF"), FileName.Parse("\u00FF"));
    }

    [Fact]
    public void CaseIsPreservedAsWritten()
    {
        Assert.Equal("AçÃo", FileName.Parse("AçÃo").Value);
        Assert.Equal([0x41, 0xE7, 0xC3, 0x6F], FileName.Parse("AçÃo").Bytes.ToArray());
    }

    [Fact]
    public void DecomposedInputIsNormalizedToIso88591()
    {
        string decomposed = "Ac\u0327a\u0303o";
        Assert.NotEqual(decomposed, decomposed.Normalize(NormalizationForm.FormC));
        Assert.Equal([0x41, 0xE7, 0xE3, 0x6F], FileName.Parse(decomposed).Bytes.ToArray());
        Assert.Equal(FileName.Parse("Ação"), FileName.Parse(decomposed));
    }

    [Theory]
    [InlineData("")]
    [InlineData(".")]
    [InlineData("..")]
    [InlineData("a/b")]
    [InlineData("tab\there")]
    [InlineData("del\u007F")]
    [InlineData("c1\u0085")]
    [InlineData("euro\u20AC")]
    [InlineData("emoji\U0001F600")]
    [InlineData("0123456789012345678901234567890")]
    public void InvalidNamesAreRejectedWithEinval(string name)
    {
        Assert.Equal(C5fsError.EINVAL, TestSupport.ErrorOf(() => FileName.Parse(name)));
    }

    [Fact]
    public void NonLatin1CharactersGiveAClearError()
    {
        C5fsException error = Assert.Throws<C5fsException>(() => FileName.Parse("price\u20AC"));
        Assert.Contains("U+20AC", error.Message, StringComparison.Ordinal);
        Assert.Contains("ISO-8859-1", error.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("012345678901234567890123456789")]
    [InlineData("a b")]
    [InlineData("...")]
    [InlineData(".profile")]
    [InlineData("\u00A0nbsp")]
    [InlineData("ÿ")]
    public void ValidNamesAreAccepted(string name)
    {
        Assert.Equal(name, FileName.Parse(name).Value);
    }

    [Fact]
    public void PathsAreAbsoluteAndCollapseRepeatedSlashes()
    {
        Assert.Equal("/a/b", VolumePath.Parse("//a///b/").ToString());
        Assert.True(VolumePath.Parse("/").IsRoot);
        Assert.Equal(VolumePath.Parse("/SYS/Kernel"), Volume.KernelPath);
        Assert.Equal(C5fsError.EINVAL, TestSupport.ErrorOf(() => VolumePath.Parse("a/b")));
        Assert.Equal(C5fsError.EINVAL, TestSupport.ErrorOf(() => VolumePath.Parse("/a/../b")));
    }

    [Fact]
    public void PathsAreLimitedTo127Bytes()
    {
        string segment = new('x', 30);
        string path127 = $"/{segment}/{segment}/{segment}/{segment}/{new string('y', 2)}";
        Assert.Equal(127, path127.Length);
        Assert.Equal(path127, VolumePath.Parse(path127).ToString());
        Assert.Equal(C5fsError.EINVAL, TestSupport.ErrorOf(() => VolumePath.Parse(path127 + "z")));
    }
}
