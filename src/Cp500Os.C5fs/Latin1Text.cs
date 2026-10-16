using System.Text;

namespace Cp500Os.C5fs;

internal static class Latin1Text
{
    /// <summary>Converts a host string to ISO-8859-1, rejecting characters outside it.</summary>
    /// <remarks>Normalizes to NFC first so a decomposed "a" plus combining tilde still maps to 0xE3.</remarks>
    public static byte[] Encode(string text, string what)
    {
        string normalized = text.Normalize(NormalizationForm.FormC);
        byte[] bytes = new byte[normalized.Length];
        for (int i = 0; i < normalized.Length; i++)
        {
            char c = normalized[i];
            if (c > 0xFF)
            {
                throw new C5fsException(
                    C5fsError.EINVAL,
                    $"{what} '{text}' contains '{c}' (U+{(int)c:X4}), which is not in ISO-8859-1");
            }

            bytes[i] = (byte)c;
        }

        return bytes;
    }

    public static string Decode(ReadOnlySpan<byte> bytes) => Encoding.Latin1.GetString(bytes);

    public static bool IsPrintable(byte value) => value is (>= 0x20 and <= 0x7E) or >= 0xA0;

    /// <summary>ISO-8859-1 lower-case folding: A-Z and the accented capitals 0xC0-0xDE except 0xD7 (multiplication sign).</summary>
    public static byte Fold(byte value) =>
        value is (>= (byte)'A' and <= (byte)'Z') or (>= 0xC0 and <= 0xDE and not 0xD7)
            ? (byte)(value + 0x20)
            : value;
}
