namespace Cp500Os.C5x;

/// <summary>The relocation the kernel loader performs. Kernel loader tests use it as their oracle.</summary>
public static class Relocator
{
    /// <summary>Returns a copy of <paramref name="image"/> with <paramref name="loadPage"/> added (mod 256) to every marked byte.</summary>
    public static byte[] Relocate(ReadOnlySpan<byte> image, RelocationBitmap bitmap, byte loadPage)
    {
        ArgumentNullException.ThrowIfNull(bitmap);
        if (image.Length != bitmap.Length)
            throw new ArgumentException($"The bitmap covers {bitmap.Length} bytes but the image has {image.Length}.", nameof(bitmap));

        byte[] relocated = image.ToArray();
        ReadOnlySpan<byte> bits = bitmap.Bytes;
        for (int i = 0; i < relocated.Length; i++)
        {
            if ((bits[i / 8] & (1 << (i % 8))) != 0)
                relocated[i] += loadPage;
        }

        return relocated;
    }
}
