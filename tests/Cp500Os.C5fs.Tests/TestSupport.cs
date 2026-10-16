using System.Buffers.Binary;

namespace Cp500Os.C5fs.Tests;

internal sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
{
    public DateTimeOffset Now { get; set; } = now;

    public override DateTimeOffset GetUtcNow() => Now;

    public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;
}

internal static class TestSupport
{
    /// <summary>2026-10-16 10:00:00 as seconds since 1980-01-01.</summary>
    public const uint StartSeconds = 1_476_612_000;

    public const uint VolumeId = 0x12345678;

    public static FixedTimeProvider Clock() => new(new DateTimeOffset(2026, 10, 16, 10, 0, 0, TimeSpan.Zero));

    public static Volume Format(VolumeGeometry geometry, TimeProvider? time = null, string label = "TEST") =>
        Volume.Format(new FormatOptions
        {
            Geometry = geometry,
            Label = label,
            VolumeId = VolumeId,
            TimeProvider = time ?? Clock(),
        });

    public static Volume Format360() => Format(VolumeGeometry.Floppy360);

    public static Volume Format180() => Format(VolumeGeometry.Floppy180);

    public static byte[] Pattern(int length, int seed = 1)
    {
        byte[] bytes = new byte[length];
        for (int i = 0; i < length; i++)
        {
            bytes[i] = (byte)((i * 31) + (i >> 8) + seed);
        }

        return bytes;
    }

    public static Span<byte> Block(byte[] image, int block) => image.AsSpan(block * 256, 256);

    public static uint SequenceIn(byte[] image, SuperblockCopy copy) =>
        BinaryPrimitives.ReadUInt32LittleEndian(Block(image, (int)copy)[6..]);

    public static ushort GenerationIn(byte[] image, SuperblockCopy copy) =>
        BinaryPrimitives.ReadUInt16LittleEndian(Block(image, (int)copy)[14..]);

    public static bool IsBitSet(byte[] image, int block) => (image[(3 * 256) + (block / 8)] & (1 << (block % 8))) != 0;

    /// <summary>The volume is consistent now and after a save and reopen.</summary>
    public static void AssertConsistent(Volume volume)
    {
        Assert.Empty(volume.Check());
        Assert.Empty(Volume.Open(volume.ToImage()).Check());
    }

    public static C5fsError ErrorOf(Action action) => Assert.Throws<C5fsException>(action).Error;
}
