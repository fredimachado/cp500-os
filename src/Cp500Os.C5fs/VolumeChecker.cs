namespace Cp500Os.C5fs;

/// <summary>Full consistency check (what fsck verifies). Collects problems instead of stopping at the first.</summary>
internal sealed class VolumeChecker(
    BlockStore store,
    Superblock superblock,
    Bitmap bitmap,
    InodeTable inodes,
    DirectoryTable directories)
{
    private readonly VolumeGeometry _geometry = superblock.Geometry;
    private readonly List<string> _problems = [];
    private readonly Dictionary<int, InodeRecord> _allocated = [];
    private readonly Dictionary<int, int> _references = [];

    public IReadOnlyList<string> Run()
    {
        ReadInodes();
        CheckBlockOwnership();
        CheckTree();
        CheckReferences();
        CheckKernel();
        return _problems;
    }

    private void ReadInodes()
    {
        if (store.Read(_geometry.InodeTableStart)[..Inode.RecordSize].ContainsAnyExcept((byte)0))
        {
            _problems.Add("inode slot 0 is reserved but not zero");
        }

        for (int number = InodeTable.RootNumber; number < _geometry.InodeCount; number++)
        {
            if (inodes.IsFree(number))
            {
                if (inodes.RawSlot(number).ContainsAnyExcept((byte)0))
                {
                    _problems.Add($"inode {number} is free but its slot is not zeroed");
                }

                continue;
            }

            try
            {
                _allocated[number] = inodes.Read(number)!;
            }
            catch (C5fsException e)
            {
                _problems.Add(e.Message);
            }
        }
    }

    private void CheckBlockOwnership()
    {
        string?[] owners = new string?[_geometry.BlockCount];
        for (int block = 0; block < _geometry.FirstDataBlock; block++)
        {
            owners[block] = "metadata";
        }

        foreach ((int number, InodeRecord record) in _allocated)
        {
            foreach (int block in record.Inode.Extents.SelectMany(extent => extent.Blocks))
            {
                Claim(owners, block, $"inode {number}");
            }

            if (record.IndirectBlock is ushort indirect)
            {
                Claim(owners, indirect, $"inode {number} (indirect block)");
            }
        }

        for (int block = 0; block < _geometry.BlockCount; block++)
        {
            bool used = bitmap.IsUsed(block);
            if (used && owners[block] is null)
            {
                _problems.Add($"block {block} is marked used but nothing owns it");
            }
            else if (!used && owners[block] is { } owner)
            {
                _problems.Add($"block {block} is owned by {owner} but marked free");
            }
        }

        for (int bit = _geometry.BlockCount; bit < bitmap.PaddedBitCount; bit++)
        {
            if (!bitmap.IsUsed(bit))
            {
                _problems.Add($"bitmap padding bit {bit} (past the last block) is not set");
                break;
            }
        }
    }

    private void Claim(string?[] owners, int block, string owner)
    {
        if (owners[block] is { } other)
        {
            _problems.Add($"block {block} is owned by both {other} and {owner}");
        }
        else
        {
            owners[block] = owner;
        }
    }

    private void CheckTree()
    {
        if (!_allocated.TryGetValue(InodeTable.RootNumber, out InodeRecord? root) || !root.Inode.IsDirectory)
        {
            _problems.Add("inode 1 (the root directory) is not a valid directory");
            return;
        }

        HashSet<int> visited = [InodeTable.RootNumber];
        Stack<(int Number, int Parent, string Path)> pending = new([(InodeTable.RootNumber, InodeTable.RootNumber, "/")]);
        while (pending.TryPop(out (int Number, int Parent, string Path) directory))
        {
            foreach ((int child, string path) in CheckDirectory(directory.Number, directory.Parent, directory.Path))
            {
                if (_allocated[child].Inode.IsDirectory && visited.Add(child))
                {
                    pending.Push((child, directory.Number, path));
                }
            }
        }
    }

    /// <summary>Checks one directory's entries and returns the valid children it references.</summary>
    private List<(int Number, string Path)> CheckDirectory(int number, int parent, string path)
    {
        IReadOnlyList<DirectorySlot> slots = directories.ReadSlots(_allocated[number].Inode);
        if (slots[0].InodeNumber != parent || !slots[0].HasParentName)
        {
            _problems.Add($"directory '{path}': the first entry must be '..' pointing at inode {parent}");
        }

        List<(int, string)> children = [];
        HashSet<FileName> names = [];
        foreach (DirectorySlot slot in slots.Skip(1))
        {
            if (slot.IsFree)
            {
                if (!slot.IsZeroed)
                {
                    _problems.Add($"directory '{path}': free entry {slot.Index} is not zeroed");
                }

                continue;
            }

            FileName? name = slot.Name;
            string childPath = $"{path.TrimEnd('/')}/{name?.Value ?? $"<entry {slot.Index}>"}";
            if (name is null)
            {
                _problems.Add($"directory '{path}': entry {slot.Index} has an invalid name");
            }
            else if (!names.Add(name))
            {
                _problems.Add($"directory '{path}': duplicate name '{name}' (names compare case-insensitively)");
            }

            if (!_allocated.ContainsKey(slot.InodeNumber))
            {
                _problems.Add($"'{childPath}' points at inode {slot.InodeNumber}, which is free, invalid or out of range");
                continue;
            }

            _references[slot.InodeNumber] = _references.GetValueOrDefault(slot.InodeNumber) + 1;
            children.Add((slot.InodeNumber, childPath));
        }

        return children;
    }

    private void CheckReferences()
    {
        foreach (int number in _allocated.Keys)
        {
            int references = _references.GetValueOrDefault(number);
            if (number == InodeTable.RootNumber)
            {
                if (references > 0)
                {
                    _problems.Add("the root directory is referenced by a directory entry other than '..'");
                }
            }
            else if (references == 0)
            {
                _problems.Add($"inode {number} is allocated but no directory entry points at it");
            }
            else if (references > 1)
            {
                _problems.Add($"inode {number} has {references} directory entries; hard links are not supported");
            }
        }
    }

    private void CheckKernel()
    {
        Inode? kernel = FindKernel();
        Extent? recorded = superblock.Kernel;
        if (kernel is null)
        {
            if (recorded is not null)
            {
                _problems.Add($"the superblock records a kernel at blocks {recorded} but {Volume.KernelPath} does not exist");
            }
        }
        else if (kernel.IsDirectory)
        {
            _problems.Add($"{Volume.KernelPath} is a directory");
        }
        else if (recorded is null)
        {
            _problems.Add($"{Volume.KernelPath} exists but the superblock records no kernel");
        }
        else if (kernel.Extents is not [Extent only] || only != recorded)
        {
            _problems.Add(
                $"the superblock kernel run {recorded} does not match {Volume.KernelPath}'s extents {string.Join(", ", kernel.Extents)}");
        }
    }

    private Inode? FindKernel()
    {
        try
        {
            Inode current = inodes.Get(InodeTable.RootNumber);
            foreach (FileName segment in Volume.KernelPath.Segments)
            {
                if (!current.IsDirectory || directories.Find(current, segment) is not { } slot)
                {
                    return null;
                }

                current = inodes.Get(slot.InodeNumber);
            }

            return current;
        }
        catch (C5fsException)
        {
            return null;
        }
    }
}
