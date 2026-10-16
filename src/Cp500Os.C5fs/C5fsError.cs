namespace Cp500Os.C5fs;

/// <summary>Error numbers shared with the kernel (design section 6).</summary>
public enum C5fsError
{
    None = 0,
    ENOENT = 1,
    EEXIST = 2,
    ENOMEM = 3,
    EBADF = 4,
    EINVAL = 5,
    ENOSPC = 6,
    EIO = 7,
    ENOTDIR = 8,
    EISDIR = 9,
    ENOEXEC = 10,
    EMFILE = 11,
    ECHILD = 12,
    EROFS = 13,
    ENOTEMPTY = 14,
    EBUSY = 15,
    EAGAIN = 16,
    ECHANGED = 17,
    ENODEV = 18,
}
