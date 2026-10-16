using System.Buffers.Binary;
using System.Collections.Immutable;
using System.Security.Cryptography;

namespace Cp500Os.C5fs;

/// <summary>
/// An in-memory C5FS volume. Every mutating operation either completes or leaves the volume
/// exactly as it was. <see cref="ToImage"/> commits the session: it writes the next superblock
/// copy (sequence + 1, generation + 1, clean) when anything changed.
/// </summary>
public sealed class Volume
{
    public const int MaxKernelBlocks = Extent.MaxLength;

    private readonly BlockStore _store;
    private readonly Bitmap _bitmap;
    private readonly BlockAllocator _allocator;
    private readonly InodeTable _inodes;
    private readonly DirectoryTable _directories;
    private readonly TimeProvider _time;
    private Superblock _superblock;
    private SessionState _state;

    private Volume(byte[] image, Superblock superblock, SuperblockCopy activeCopy, SessionState state, TimeProvider time)
    {
        _store = new BlockStore(image);
        _bitmap = new Bitmap(_store, superblock.Geometry);
        _allocator = new BlockAllocator(_bitmap);
        _inodes = new InodeTable(_store, superblock.Geometry, _allocator);
        _directories = new DirectoryTable(_store, _inodes, _allocator);
        _superblock = superblock;
        _time = time;
        _state = state;
        ActiveCopy = activeCopy;
    }

    private enum SessionState
    {
        Formatted,
        Clean,
        Dirty,
    }

    public static VolumePath KernelPath { get; } = VolumePath.Parse("/sys/kernel");

    public Superblock Superblock => _superblock;

    /// <summary>The superblock copy that is current: chosen at open, or the one written by the last save.</summary>
    public SuperblockCopy ActiveCopy { get; private set; }

    public VolumeGeometry Geometry => _superblock.Geometry;

    public int FreeBlocks => _bitmap.CountFree();

    public int FreeInodes => _inodes.CountFree();

    public static Volume Format(FormatOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        C5Time now = C5Time.Now(options.TimeProvider);
        Superblock superblock = new()
        {
            Geometry = options.Geometry,
            VolumeId = options.VolumeId ?? BinaryPrimitives.ReadUInt32LittleEndian(RandomNumberGenerator.GetBytes(4)),
            Sequence = 0,
            Generation = 1,
            Clean = true,
            Kernel = null,
            Created = now,
            LastWritten = now,
            Label = options.Label,
        };

        Volume volume = new(
            new byte[options.Geometry.ImageSize], superblock, SuperblockCopy.B, SessionState.Formatted, options.TimeProvider);
        volume._bitmap.Initialize();
        Extent rootBlock = volume._directories.CreateEmpty(InodeTable.RootNumber);
        volume._inodes.Write(
            InodeTable.RootNumber,
            new Inode(InodeKind.Directory, InodeAttributes.None, Inode.DirectoryEntrySize, now, now, [rootBlock]));
        return volume;
    }

    /// <summary>Opens a copy of an image. The valid superblock copy (magic and CRC) with the higher sequence wins; a tie goes to A.</summary>
    public static Volume Open(ReadOnlySpan<byte> image, TimeProvider? timeProvider = null)
    {
        const int blockSize = VolumeGeometry.BlockSize;
        if (image.Length < 3 * blockSize || image.Length % blockSize != 0)
        {
            throw new C5fsException(
                C5fsError.EINVAL, $"image is {image.Length} bytes, not a whole number of 256-byte blocks holding a superblock");
        }

        ReadOnlySpan<byte> a = image.Slice((int)SuperblockCopy.A * blockSize, blockSize);
        ReadOnlySpan<byte> b = image.Slice((int)SuperblockCopy.B * blockSize, blockSize);
        SuperblockCopy active = (Superblock.IsValidCopy(a), Superblock.IsValidCopy(b)) switch
        {
            (true, true) => SequenceOf(b) > SequenceOf(a) ? SuperblockCopy.B : SuperblockCopy.A,
            (true, false) => SuperblockCopy.A,
            (false, true) => SuperblockCopy.B,
            (false, false) => throw new C5fsException(
                C5fsError.EIO, "not a C5FS volume: both superblock copies fail the magic or CRC check"),
        };

        Superblock superblock = Superblock.Parse(active == SuperblockCopy.A ? a : b);
        if (image.Length != superblock.Geometry.ImageSize)
        {
            throw new C5fsException(
                C5fsError.EINVAL,
                $"image is {image.Length} bytes but its superblock describes {superblock.Geometry.BlockCount} blocks ({superblock.Geometry.ImageSize} bytes)");
        }

        Volume volume = new(image.ToArray(), superblock, active, SessionState.Clean, timeProvider ?? TimeProvider.System);
        if (volume._inodes.Read(InodeTable.RootNumber)?.Inode.IsDirectory != true)
        {
            throw new C5fsException(C5fsError.EIO, "inode 1 (the root directory) is not a directory");
        }

        return volume;
    }

    public FileStatus Stat(string path)
    {
        (ushort number, Inode inode) = Resolve(VolumePath.Parse(path));
        return new FileStatus(number, inode);
    }

    /// <summary>The entries of a directory in stored order, without "..".</summary>
    public IReadOnlyList<DirectoryListing> List(string path)
    {
        (_, Inode directory) = ResolveDirectory(VolumePath.Parse(path));
        return
        [
            .. _directories.Entries(directory).Select(entry =>
                new DirectoryListing(entry.Name, new FileStatus(entry.Slot.InodeNumber, _inodes.Get(entry.Slot.InodeNumber)))),
        ];
    }

    public byte[] ReadFile(string path)
    {
        VolumePath parsed = VolumePath.Parse(path);
        (_, Inode inode) = Resolve(parsed);
        return inode.IsDirectory
            ? throw new C5fsException(C5fsError.EISDIR, $"'{parsed}' is a directory")
            : FileContent.Read(_store, inode);
    }

    public void CreateDirectory(string path, bool createParents = false)
    {
        VolumePath parsed = VolumePath.Parse(path);
        using Mutation mutation = BeginMutation();
        ushort current = InodeTable.RootNumber;
        VolumePath walked = VolumePath.Root;
        if (parsed.IsRoot && !createParents)
        {
            throw new C5fsException(C5fsError.EEXIST, "'/' already exists");
        }

        foreach (FileName segment in parsed.Segments)
        {
            walked = walked.Append(segment);
            bool last = walked.Equals(parsed);
            if (_directories.Find(_inodes.Get(current), segment) is { } existing)
            {
                Inode inode = _inodes.Get(existing.InodeNumber);
                if (last && !(createParents && inode.IsDirectory))
                {
                    throw new C5fsException(C5fsError.EEXIST, $"'{walked}' already exists");
                }

                current = inode.IsDirectory
                    ? existing.InodeNumber
                    : throw new C5fsException(C5fsError.ENOTDIR, $"'{walked}' is not a directory");
            }
            else
            {
                current = !last && !createParents
                    ? throw new C5fsException(C5fsError.ENOENT, $"'{walked}' does not exist")
                    : MakeDirectory(current, segment, mutation.Now);
            }
        }

        mutation.Complete();
    }

    /// <summary>Creates or replaces a file. Replacing keeps the inode number, attributes and creation time.</summary>
    public void WriteFile(string path, ReadOnlySpan<byte> content)
    {
        VolumePath parsed = VolumePath.Parse(path);
        if (parsed.IsRoot)
        {
            throw new C5fsException(C5fsError.EISDIR, "'/' is a directory");
        }

        if (parsed.Equals(KernelPath))
        {
            throw new C5fsException(
                C5fsError.EINVAL, $"'{parsed}' must be one contiguous run recorded in the superblock; install it as the kernel (c5fs sys --kernel)");
        }

        if (content.Length > Inode.MaxSize)
        {
            throw new C5fsException(C5fsError.EINVAL, $"{content.Length} bytes is more than the {Inode.MaxSize}-byte file size limit");
        }

        using Mutation mutation = BeginMutation();
        (ushort parent, _) = ResolveDirectory(parsed.Parent);
        WriteContent(parent, parsed, content, mutation.Now, contiguous: false);
        mutation.Complete();
    }

    /// <summary>Removes a file or an empty directory. Removing /sys/kernel clears the superblock's kernel run.</summary>
    public void Remove(string path)
    {
        VolumePath parsed = VolumePath.Parse(path);
        if (parsed.IsRoot)
        {
            throw new C5fsException(C5fsError.EBUSY, "the root directory cannot be removed");
        }

        using Mutation mutation = BeginMutation();
        (ushort parent, Inode parentInode) = ResolveDirectory(parsed.Parent);
        DirectorySlot slot = _directories.Find(parentInode, parsed.Name)
            ?? throw new C5fsException(C5fsError.ENOENT, $"'{parsed}' does not exist");
        Inode inode = _inodes.Get(slot.InodeNumber);
        if (inode.IsDirectory && _directories.Entries(inode).Any())
        {
            throw new C5fsException(C5fsError.ENOTEMPTY, $"directory '{parsed}' is not empty");
        }

        _directories.Remove(parent, slot.Index, mutation.Now);
        _inodes.Release(slot.InodeNumber);
        if (parsed.Equals(KernelPath))
        {
            _superblock = _superblock with { Kernel = null };
        }

        mutation.Complete();
    }

    public byte[] ReadBootSector() => _store.Read(0).ToArray();

    /// <summary>Writes up to 256 bytes of boot code to block 0, zero-padded.</summary>
    public void InstallBootSector(ReadOnlySpan<byte> code)
    {
        if (code.IsEmpty || code.Length > VolumeGeometry.BlockSize)
        {
            throw new C5fsException(
                C5fsError.EINVAL, $"a boot sector is 1-{VolumeGeometry.BlockSize} bytes, got {code.Length}");
        }

        using Mutation mutation = BeginMutation();
        Span<byte> block = _store.Write(0);
        block.Clear();
        code.CopyTo(block);
        mutation.Complete();
    }

    /// <summary>
    /// Installs /sys/kernel as one contiguous extent (first fit) and records it in the superblock,
    /// replacing any previous kernel. Creates /sys when missing.
    /// </summary>
    public void InstallKernel(ReadOnlySpan<byte> kernel)
    {
        int blocks = Inode.BlocksFor(kernel.Length);
        if (kernel.IsEmpty || blocks > MaxKernelBlocks)
        {
            throw new C5fsException(
                C5fsError.EINVAL,
                $"a kernel is 1-{MaxKernelBlocks * VolumeGeometry.BlockSize} bytes (one extent of at most {MaxKernelBlocks} blocks), got {kernel.Length}");
        }

        using Mutation mutation = BeginMutation();
        VolumePath sys = KernelPath.Parent;
        ushort sysNumber = _directories.Find(_inodes.Get(InodeTable.RootNumber), sys.Name) is { } found
            ? (_inodes.Get(found.InodeNumber).IsDirectory
                ? found.InodeNumber
                : throw new C5fsException(C5fsError.ENOTDIR, $"'{sys}' is not a directory"))
            : MakeDirectory(InodeTable.RootNumber, sys.Name, mutation.Now);

        Extent run = WriteContent(sysNumber, KernelPath, kernel, mutation.Now, contiguous: true).Extents.Single();
        _superblock = _superblock with { Kernel = run };
        mutation.Complete();
    }

    /// <summary>Checks the whole volume; returns an empty list when it is consistent.</summary>
    public IReadOnlyList<string> Check() =>
        new VolumeChecker(_store, _superblock, _bitmap, _inodes, _directories).Run();

    /// <summary>Saves the session and returns a copy of the image.</summary>
    /// <remarks>
    /// A freshly formatted volume gets both copies (A sequence 1, B sequence 2). Otherwise, when anything
    /// changed since the last save, the copy that is not active gets sequence + 1 and generation + 1.
    /// The clean flag is always set, because the host writes the whole image at once.
    /// </remarks>
    public byte[] ToImage()
    {
        C5Time now = C5Time.Now(_time);
        switch (_state)
        {
            case SessionState.Formatted:
                WriteSuperblock(SuperblockCopy.A, _superblock with { Sequence = 1, LastWritten = now });
                WriteSuperblock(SuperblockCopy.B, _superblock with { Sequence = 2, LastWritten = now });
                break;
            case SessionState.Dirty:
                WriteSuperblock(
                    ActiveCopy == SuperblockCopy.A ? SuperblockCopy.B : SuperblockCopy.A,
                    _superblock with
                    {
                        Sequence = _superblock.Sequence + 1,
                        Generation = unchecked((ushort)(_superblock.Generation + 1)),
                        Clean = true,
                        LastWritten = now,
                    });
                break;
            case SessionState.Clean:
                break;
            default:
                throw new InvalidOperationException($"Unknown session state {_state}.");
        }

        _state = SessionState.Clean;
        return _store.ToArray();
    }

    private void WriteSuperblock(SuperblockCopy copy, Superblock superblock)
    {
        superblock.Serialize().CopyTo(_store.Write((int)copy));
        _superblock = superblock;
        ActiveCopy = copy;
    }

    private static uint SequenceOf(ReadOnlySpan<byte> block) => BinaryPrimitives.ReadUInt32LittleEndian(block[6..]);

    private (ushort Number, Inode Inode) Resolve(VolumePath path)
    {
        ushort number = InodeTable.RootNumber;
        Inode inode = _inodes.Get(number);
        VolumePath walked = VolumePath.Root;
        foreach (FileName segment in path.Segments)
        {
            if (!inode.IsDirectory)
            {
                throw new C5fsException(C5fsError.ENOTDIR, $"'{walked}' is not a directory");
            }

            walked = walked.Append(segment);
            number = _directories.Find(inode, segment)?.InodeNumber
                ?? throw new C5fsException(C5fsError.ENOENT, $"'{walked}' does not exist");
            inode = _inodes.Get(number);
        }

        return (number, inode);
    }

    private (ushort Number, Inode Inode) ResolveDirectory(VolumePath path)
    {
        (ushort number, Inode inode) = Resolve(path);
        return inode.IsDirectory
            ? (number, inode)
            : throw new C5fsException(C5fsError.ENOTDIR, $"'{path}' is not a directory");
    }

    private ushort MakeDirectory(ushort parent, FileName name, C5Time now)
    {
        ushort number = _inodes.Allocate();
        Extent block = _directories.CreateEmpty(parent);
        _inodes.Write(number, new Inode(InodeKind.Directory, InodeAttributes.None, Inode.DirectoryEntrySize, now, now, [block]));
        _directories.Add(parent, name, number, now);
        return number;
    }

    private Inode WriteContent(ushort parent, VolumePath path, ReadOnlySpan<byte> content, C5Time now, bool contiguous)
    {
        DirectorySlot? existing = _directories.Find(_inodes.Get(parent), path.Name);
        Inode? previous = existing is null ? null : _inodes.Get(existing.InodeNumber);
        if (previous?.IsDirectory == true)
        {
            throw new C5fsException(C5fsError.EISDIR, $"'{path}' is a directory");
        }

        if (previous is not null)
        {
            _allocator.Free(previous.Extents);
        }

        int blocks = Inode.BlocksFor(content.Length);
        ImmutableArray<Extent> extents = blocks == 0 ? []
            : contiguous ? [_allocator.AllocateContiguous(blocks)]
            : _allocator.Grow([], blocks);
        FileContent.Write(_store, extents, content);

        Inode inode = new(
            InodeKind.File, previous?.Attributes ?? InodeAttributes.None, content.Length, now, previous?.Created ?? now, extents);
        ushort number = existing?.InodeNumber ?? _inodes.Allocate();
        _inodes.Write(number, inode);
        if (existing is null)
        {
            _directories.Add(parent, path.Name, number, now);
        }

        return inode;
    }

    private Mutation BeginMutation()
    {
        _store.BeginTransaction();
        return new Mutation(this);
    }

    private sealed class Mutation(Volume volume) : IDisposable
    {
        private readonly Superblock _superblock = volume._superblock;
        private bool _completed;

        public C5Time Now { get; } = C5Time.Now(volume._time);

        public void Complete()
        {
            if (volume._store.CommitTransaction() && volume._state == SessionState.Clean)
            {
                volume._state = SessionState.Dirty;
            }

            _completed = true;
        }

        public void Dispose()
        {
            if (!_completed)
            {
                volume._store.RollbackTransaction();
                volume._superblock = _superblock;
            }
        }
    }
}
