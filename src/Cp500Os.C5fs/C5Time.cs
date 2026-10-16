using System.Globalization;

namespace Cp500Os.C5fs;

/// <summary>Seconds since 1980-01-01 00:00 local time, unsigned 32-bit.</summary>
public readonly record struct C5Time(uint Seconds)
{
    public static readonly DateTime Epoch = new(1980, 1, 1, 0, 0, 0, DateTimeKind.Unspecified);

    /// <summary>The local wall-clock time this value stands for.</summary>
    public DateTime ToDateTime() => Epoch.AddSeconds(Seconds);

    /// <summary>Converts a local wall-clock time, clamping to the representable range.</summary>
    public static C5Time FromDateTime(DateTime localTime)
    {
        long seconds = (localTime - Epoch).Ticks / TimeSpan.TicksPerSecond;
        return new C5Time((uint)Math.Clamp(seconds, 0, uint.MaxValue));
    }

    public static C5Time Now(TimeProvider timeProvider)
    {
        ArgumentNullException.ThrowIfNull(timeProvider);
        return FromDateTime(timeProvider.GetLocalNow().DateTime);
    }

    public override string ToString() => ToDateTime().ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
}
