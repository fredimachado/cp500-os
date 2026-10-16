using System.CommandLine;
using System.CommandLine.Parsing;
using System.Globalization;
using Cp500Os.C5x;

namespace Cp500Os.MkReloc.Cli;

/// <summary>
/// <c>mkreloc &lt;link0000.bin&gt; &lt;link0100.bin&gt; -o &lt;out.c5x&gt; [--bss n] [--stack n] [--entry n]</c>
/// builds a C5X program; <c>mkreloc --info &lt;file.c5x&gt;</c> prints its header.
/// </summary>
public static class MkRelocCommand
{
    public const ushort DefaultBssSize = 0;
    public const ushort DefaultStackSize = 256;
    public const ushort DefaultEntryOffset = 0;

    public static int Run(string[] args, TextWriter output, TextWriter error)
    {
        var link0000 = new Argument<FileInfo?>("link0000.bin")
        {
            Description = "The program linked at 0000h.",
            Arity = ArgumentArity.ZeroOrOne,
        };
        var link0100 = new Argument<FileInfo?>("link0100.bin")
        {
            Description = "The same program linked at 0100h.",
            Arity = ArgumentArity.ZeroOrOne,
        };
        var outputFile = new Option<FileInfo?>("--output", "-o") { Description = "The C5X file to write.", HelpName = "out.c5x" };
        var bss = NumberOption("--bss", DefaultBssSize, "Bytes of zeroed data after the image.");
        var stack = NumberOption("--stack", DefaultStackSize, "Stack bytes the program needs; the loader adds the 192-byte kernel reserve.");
        var entry = NumberOption("--entry", DefaultEntryOffset, "Entry point as an offset into the image.");
        var info = new Option<FileInfo?>("--info") { Description = "Print the header of an existing C5X file instead.", HelpName = "file.c5x" };

        var root = new RootCommand("Builds a relocatable C5X program for cp500-os from two links of the same code.")
        {
            link0000, link0100, outputFile, bss, stack, entry, info,
        };
        root.Validators.Add(result =>
        {
            bool hasLinks = result.GetValue(link0000) is not null || result.GetValue(link0100) is not null;
            if (result.GetValue(info) is not null)
            {
                if (hasLinks || result.GetValue(outputFile) is not null)
                    result.AddError("--info takes a single C5X file and no links or --output.");
            }
            else if (result.GetValue(link0000) is null || result.GetValue(link0100) is null || result.GetValue(outputFile) is null)
            {
                result.AddError("Expected <link0000.bin> <link0100.bin> -o <out.c5x>, or --info <file.c5x>.");
            }
        });

        root.SetAction(parsed =>
        {
            try
            {
                if (parsed.GetValue(info) is { } c5x)
                {
                    PrintInfo(C5xFile.Parse(File.ReadAllBytes(c5x.FullName)), output);
                    return 0;
                }

                var program = C5xProgram.FromLinks(
                    File.ReadAllBytes(parsed.GetValue(link0000)!.FullName),
                    File.ReadAllBytes(parsed.GetValue(link0100)!.FullName),
                    parsed.GetValue(bss),
                    parsed.GetValue(stack),
                    parsed.GetValue(entry));
                File.WriteAllBytes(parsed.GetValue(outputFile)!.FullName, C5xFile.Write(program));
                return 0;
            }
            catch (Exception exception) when (exception is C5xException or IOException or UnauthorizedAccessException)
            {
                error.WriteLine($"mkreloc: {exception.Message}");
                return 1;
            }
        });

        return root.Parse(args).Invoke(new InvocationConfiguration { Output = output, Error = error });
    }

    private static void PrintInfo(C5xProgram program, TextWriter output)
    {
        var header = program.Header;
        var culture = CultureInfo.InvariantCulture;
        output.WriteLine(string.Create(culture, $"version      {C5xFile.Version}"));
        output.WriteLine(string.Create(culture, $"image        {header.ImageSize} bytes"));
        output.WriteLine(string.Create(culture, $"bss          {header.BssSize} bytes"));
        output.WriteLine(string.Create(culture, $"stack        {header.StackSize} bytes (+{ArenaLimits.KernelStackReserve} kernel reserve)"));
        output.WriteLine(string.Create(culture, $"entry        {header.EntryOffset:X4}h"));
        output.WriteLine(string.Create(culture, $"relocations  {program.Relocations.MarkedOffsets().Count()}"));
        output.WriteLine(string.Create(culture, $"memory       {header.MemoryBytes} bytes, {header.MemoryPages} pages"));
    }

    private static Option<ushort> NumberOption(string name, ushort defaultValue, string description) => new(name)
    {
        Description = $"{description} Decimal or 0x hex.",
        HelpName = "n",
        DefaultValueFactory = _ => defaultValue,
        CustomParser = ParseNumber,
    };

    private static ushort ParseNumber(ArgumentResult result)
    {
        string text = result.Tokens.Single().Value;
        bool hex = text.StartsWith("0x", StringComparison.OrdinalIgnoreCase);
        bool parsed = hex
            ? ushort.TryParse(text.AsSpan(2), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out ushort value)
            : ushort.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out value);
        if (!parsed)
            result.AddError($"'{text}' is not a number from 0 to 65535 (decimal or 0x hex).");
        return value;
    }
}
