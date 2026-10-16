using System.Runtime.InteropServices;

namespace Cp500Os.C5fs;

/// <summary>The image as 256-byte blocks. Inside a transaction every first write to a block saves its old contents for rollback.</summary>
internal sealed class BlockStore(byte[] image)
{
    private const int BlockSize = VolumeGeometry.BlockSize;

    private Dictionary<int, byte[]>? _undo;

    public ReadOnlySpan<byte> Read(int block) => image.AsSpan(block * BlockSize, BlockSize);

    public Span<byte> Write(int block)
    {
        Span<byte> span = image.AsSpan(block * BlockSize, BlockSize);
        if (_undo is not null)
        {
            ref byte[]? saved = ref CollectionsMarshal.GetValueRefOrAddDefault(_undo, block, out bool exists);
            if (!exists)
            {
                saved = span.ToArray();
            }
        }

        return span;
    }

    public void BeginTransaction()
    {
        if (_undo is not null)
        {
            throw new InvalidOperationException("Transactions do not nest.");
        }

        _undo = [];
    }

    /// <summary>Ends the transaction; true when it wrote any block.</summary>
    public bool CommitTransaction()
    {
        bool changed = _undo is { Count: > 0 };
        _undo = null;
        return changed;
    }

    public void RollbackTransaction()
    {
        foreach ((int block, byte[] contents) in _undo ?? [])
        {
            contents.CopyTo(image.AsSpan(block * BlockSize, BlockSize));
        }

        _undo = null;
    }

    public byte[] ToArray() => (byte[])image.Clone();
}
