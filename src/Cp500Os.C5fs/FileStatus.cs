namespace Cp500Os.C5fs;

public sealed record FileStatus(ushort InodeNumber, Inode Inode);

public sealed record DirectoryListing(FileName Name, FileStatus Status);
