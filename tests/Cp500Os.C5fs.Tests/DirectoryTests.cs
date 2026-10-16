using System.Buffers.Binary;
using static Cp500Os.C5fs.Tests.TestSupport;

namespace Cp500Os.C5fs.Tests;

public class DirectoryTests
{
    [Fact]
    public void NestedDirectoriesStartWithDotDotPointingAtTheirParent()
    {
        Volume volume = Format360();

        volume.CreateDirectory("/home");
        volume.CreateDirectory("/home/fredi");

        FileStatus home = volume.Stat("/home");
        FileStatus fredi = volume.Stat("/HOME/Fredi");
        Assert.Equal((2, InodeKind.Directory, "21"), (home.InodeNumber, home.Inode.Kind, string.Join(",", home.Inode.Extents)));
        Assert.Equal((3, InodeKind.Directory, "22"), (fredi.InodeNumber, fredi.Inode.Kind, string.Join(",", fredi.Inode.Extents)));
        Assert.Equal(64, home.Inode.Size);
        Assert.Equal(32, fredi.Inode.Size);

        byte[] image = volume.ToImage();
        Assert.Equal([0x02, 0x00, (byte)'h', (byte)'o', (byte)'m', (byte)'e', 0x00], Block(image, 20)[32..39].ToArray());
        Assert.Equal([0x01, 0x00, (byte)'.', (byte)'.', 0x00], Block(image, 21)[..5].ToArray());
        Assert.Equal([0x03, 0x00, (byte)'f', (byte)'r', (byte)'e', (byte)'d', (byte)'i', 0x00], Block(image, 21)[32..40].ToArray());
        Assert.Equal([0x02, 0x00, (byte)'.', (byte)'.', 0x00], Block(image, 22)[..5].ToArray());
        Assert.Equal(["fredi"], volume.List("/home").Select(entry => entry.Name.Value));
        AssertConsistent(volume);
    }

    [Fact]
    public void CreateParentsBuildsTheWholeChain()
    {
        Volume volume = Format360();

        Assert.Equal(C5fsError.ENOENT, ErrorOf(() => volume.CreateDirectory("/a/b/c")));
        volume.CreateDirectory("/a/b/c", createParents: true);

        Assert.Equal(InodeKind.Directory, volume.Stat("/a/b/c").Inode.Kind);
        Assert.Equal(C5fsError.EEXIST, ErrorOf(() => volume.CreateDirectory("/a/b")));
        volume.CreateDirectory("/a/b", createParents: true);
        volume.CreateDirectory("/", createParents: true);
        Assert.Equal(C5fsError.EEXIST, ErrorOf(() => volume.CreateDirectory("/")));
        Assert.Equal(4, volume.Stat("/a/b/c").InodeNumber);
        AssertConsistent(volume);
    }

    [Fact]
    public void ErrorsUseTheKernelErrorNumbers()
    {
        Volume volume = Format360();
        volume.CreateDirectory("/a/b", createParents: true);
        volume.WriteFile("/a/file", "x"u8);

        Assert.Equal(C5fsError.EEXIST, ErrorOf(() => volume.CreateDirectory("/a/file")));
        Assert.Equal(C5fsError.ENOTDIR, ErrorOf(() => volume.CreateDirectory("/a/file/z")));
        Assert.Equal(C5fsError.ENOTDIR, ErrorOf(() => volume.CreateDirectory("/a/file/z", createParents: true)));
        Assert.Equal(C5fsError.ENOTDIR, ErrorOf(() => volume.ReadFile("/a/file/z")));
        Assert.Equal(C5fsError.ENOTDIR, ErrorOf(() => volume.WriteFile("/a/file/z", [])));
        Assert.Equal(C5fsError.ENOTDIR, ErrorOf(() => volume.List("/a/file")));
        Assert.Equal(C5fsError.EISDIR, ErrorOf(() => volume.ReadFile("/a")));
        Assert.Equal(C5fsError.EISDIR, ErrorOf(() => volume.WriteFile("/a", [])));
        Assert.Equal(C5fsError.EISDIR, ErrorOf(() => volume.WriteFile("/", [])));
        Assert.Equal(C5fsError.ENOTEMPTY, ErrorOf(() => volume.Remove("/a")));
        Assert.Equal(C5fsError.ENOENT, ErrorOf(() => volume.Remove("/a/nope")));
        Assert.Equal(C5fsError.ENOENT, ErrorOf(() => volume.ReadFile("/nope")));
        Assert.Equal(C5fsError.ENOENT, ErrorOf(() => volume.WriteFile("/nope/f", [])));
        Assert.Equal(C5fsError.EBUSY, ErrorOf(() => volume.Remove("/")));
        Assert.Empty(volume.Check());

        volume.Remove("/a/b");
        volume.Remove("/a/file");
        volume.Remove("/a");

        Assert.Empty(volume.List("/"));
        Assert.Equal(1419, volume.FreeBlocks);
        Assert.Equal(126, volume.FreeInodes);
        AssertConsistent(volume);
    }

    [Fact]
    public void RemovedEntriesAreZeroedAndReusedBeforeGrowing()
    {
        Volume volume = Format360();
        volume.WriteFile("/f1", [1]);
        volume.WriteFile("/f2", [2]);

        volume.Remove("/f1");
        Assert.False(Block(volume.ToImage(), 20)[32..64].ContainsAnyExcept((byte)0));
        volume.WriteFile("/f3", [3]);

        Assert.Equal(["f3", "f2"], volume.List("/").Select(entry => entry.Name.Value));
        Assert.Equal(96, volume.Stat("/").Inode.Size);
        Assert.Equal(2, volume.Stat("/f3").InodeNumber);
        AssertConsistent(volume);
    }

    [Fact]
    public void DirectoriesGrowByWholeBlocks()
    {
        Volume volume = Format360();
        for (int i = 0; i < 20; i++)
        {
            volume.WriteFile($"/d{i:00}", [(byte)i]);
        }

        Inode root = volume.Stat("/").Inode;
        Assert.Equal(21 * 32, root.Size);
        Assert.Equal(3, root.BlockCount);
        Assert.Equal(20, volume.List("/").Count);
        Assert.Equal([(byte)19], volume.ReadFile("/d19"));
        AssertConsistent(volume);
    }

    [Fact]
    public void NamesConflictUnderCaseFoldingButNotAccentStripping()
    {
        Volume volume = Format360();
        volume.WriteFile("/Ação", "1"u8);

        Assert.Equal(C5fsError.EEXIST, ErrorOf(() => volume.CreateDirectory("/AÇÃO")));
        volume.WriteFile("/AÇÃO", "2"u8);
        Assert.Equal("Ação", Assert.Single(volume.List("/")).Name.Value);
        Assert.Equal("2"u8.ToArray(), volume.ReadFile("/ação"));

        volume.WriteFile("/Acao", "3"u8);
        Assert.Equal(["Ação", "Acao"], volume.List("/").Select(entry => entry.Name.Value));

        byte[] image = volume.ToImage();
        Assert.Equal([0x41, 0xE7, 0xE3, 0x6F, 0x00], Block(image, 20)[34..39].ToArray());
        AssertConsistent(volume);
    }

    [Fact]
    public void ThirtyByteNamesHaveNoTerminator()
    {
        Volume volume = Format360();
        string name = "abcdefghijklmnopqrstuvwxyz0123";

        volume.WriteFile("/" + name, []);

        byte[] image = volume.ToImage();
        Assert.Equal(2, BinaryPrimitives.ReadUInt16LittleEndian(Block(image, 20)[32..]));
        Assert.Equal(name, System.Text.Encoding.Latin1.GetString(Block(image, 20)[34..64]));
        Assert.Equal(name, Assert.Single(Volume.Open(image).List("/")).Name.Value);
        AssertConsistent(volume);
    }

    [Fact]
    public void ModificationUpdatesDirectoryTimes()
    {
        FixedTimeProvider clock = Clock();
        Volume volume = Format(VolumeGeometry.Floppy360, clock);
        clock.Now = clock.Now.AddMinutes(5);

        volume.CreateDirectory("/d");

        Assert.Equal(StartSeconds + 300, volume.Stat("/").Inode.Modified.Seconds);
        Assert.Equal(StartSeconds, volume.Stat("/").Inode.Created.Seconds);
        Assert.Equal(StartSeconds + 300, volume.Stat("/d").Inode.Created.Seconds);
        Assert.Equal(new DateTime(2026, 10, 16, 10, 5, 0), volume.Stat("/d").Inode.Modified.ToDateTime());
        AssertConsistent(volume);
    }
}
