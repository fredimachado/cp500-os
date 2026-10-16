using System.Collections.Immutable;

namespace Cp500Os.C5fs;

/// <summary>
/// Allocation policy: extend the file's last extent in place when the next blocks are free,
/// otherwise take the lowest-numbered free run that holds the rest (capped at 255 blocks),
/// otherwise the lowest-numbered free run of any size.
/// </summary>
internal sealed class BlockAllocator(Bitmap bitmap)
{
    public ImmutableArray<Extent> Grow(ImmutableArray<Extent> extents, int count)
    {
        int free = bitmap.CountFree();
        if (free < count)
        {
            throw new C5fsException(C5fsError.ENOSPC, $"no space: {count} blocks needed, {free} free");
        }

        ImmutableArray<Extent>.Builder result = extents.ToBuilder();
        int remaining = count;
        while (remaining > 0)
        {
            Extent next = ExtendLast(result, remaining) ?? TakeFreeRun(remaining);
            bitmap.Allocate(next);
            if (result.Count > 0 && result[^1].End == next.Start && result[^1].Length + next.Length <= Extent.MaxLength)
            {
                result[^1] = new Extent(result[^1].Start, result[^1].Length + next.Length);
            }
            else
            {
                result.Add(next);
            }

            remaining -= next.Length;
        }

        return result.Count <= Inode.MaxExtents
            ? result.ToImmutable()
            : throw new C5fsException(
                C5fsError.ENOSPC,
                $"free space is too fragmented: the file would need {result.Count} extents, the limit is {Inode.MaxExtents}");
    }

    public Extent AllocateContiguous(int count)
    {
        int start = bitmap.FirstFit(count)
            ?? throw new C5fsException(C5fsError.ENOSPC, $"no run of {count} contiguous free blocks");
        Extent extent = new(start, count);
        bitmap.Allocate(extent);
        return extent;
    }

    public void Free(IEnumerable<Extent> extents)
    {
        foreach (Extent extent in extents)
        {
            bitmap.Free(extent);
        }
    }

    private Extent? ExtendLast(ImmutableArray<Extent>.Builder extents, int remaining)
    {
        if (extents.Count == 0)
        {
            return null;
        }

        Extent last = extents[^1];
        int length = bitmap.FreeRunLength(last.End, Math.Min(remaining, Extent.MaxLength - last.Length));
        return length > 0 ? new Extent(last.End, length) : null;
    }

    private Extent TakeFreeRun(int remaining)
    {
        int wanted = Math.Min(remaining, Extent.MaxLength);
        if (bitmap.FirstFit(wanted) is int start)
        {
            return new Extent(start, wanted);
        }

        int first = bitmap.FirstFree() ?? throw new InvalidOperationException("Free count and bitmap disagree.");
        return new Extent(first, bitmap.FreeRunLength(first, wanted));
    }
}
