using System.Globalization;
using System.Text.RegularExpressions;
using Cp500Os.C5fs;
using Cp500Os.Tests;

namespace Cp500Os.C5fs.Tests;

public sealed class DiskLayoutTests
{
    private static readonly string HdAsm = Path.Combine(RepoPaths.Root, "kernel", "hd.asm");

    [Fact]
    public void BlockZeroFixtureUsesKernelEquates()
    {
        Dictionary<string, int> equates = ReadEquates(HdAsm);
        Assert.Equal(4, equates["PT_SLOTS"]);
        Assert.Equal(7, equates["PT_ENTRY"]);
        Assert.Equal(1, equates["PT_C5FS"]);

        byte[] block = new PartitionTable(
        [
            new PartitionEntry(1, 1, 2000),
            new PartitionEntry(2, 2001, 16000),
        ]).ToBlock();

        int stride = equates["PT_ENTRY"];
        int slots = equates["PT_SLOTS"];
        Assert.Equal(28, stride * slots);
        Assert.Equal(equates["PT_C5FS"], block[0]);
        Assert.Equal(1, block[1]);
        Assert.Equal(0xD0, block[4]);
        Assert.Equal(0x07, block[5]);
        Assert.Equal(equates["PT_C5FS"], block[stride]);
        Assert.Equal(0xD1, block[stride + 1]);
        Assert.Equal(0x80, block[stride + 4]);
        Assert.Equal(0x3E, block[stride + 5]);
    }

    [Fact]
    public void ChsMapIsOneBasedSector()
    {
        Dictionary<string, int> equates = ReadEquates(HdAsm);
        int heads = equates["HD_HEADS"];
        int spt = equates["HD_SPT"];
        Assert.Equal(8, heads);
        Assert.Equal(32, spt);

        static (int cylinder, int head, int sector) Map(int lba, int heads, int spt) =>
            (lba >> 8, (lba >> 5) & (heads - 1), (lba & 0x1F) + 1);

        Assert.Equal((0, 0, 1), Map(0, heads, spt));
        Assert.Equal((0, 1, 1), Map(32, heads, spt));
        Assert.Equal((1, 0, 1), Map(256, heads, spt));
    }

    private static Dictionary<string, int> ReadEquates(string path)
    {
        Dictionary<string, int> equates = new(StringComparer.Ordinal);
        foreach (string line in File.ReadLines(path))
        {
            Match match = Regex.Match(line, @"^\s*([A-Za-z_][A-Za-z0-9_]*)\s+equ\s+([0-9A-Fa-f]+)(h)?\s*(?:;.*)?$", RegexOptions.IgnoreCase);
            if (!match.Success)
            {
                continue;
            }

            string name = match.Groups[1].Value;
            string value = match.Groups[2].Value;
            bool hex = match.Groups[3].Success;
            equates[name] = int.Parse(
                value,
                hex ? NumberStyles.HexNumber : NumberStyles.Integer,
                CultureInfo.InvariantCulture);
        }

        return equates;
    }
}
