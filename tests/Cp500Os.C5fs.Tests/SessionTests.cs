using static Cp500Os.C5fs.Tests.TestSupport;

namespace Cp500Os.C5fs.Tests;

public class SessionTests
{
    [Fact]
    public void FreshFormatOpensWithCopyBActive()
    {
        Volume volume = Volume.Open(Format360().ToImage());

        Assert.Equal(SuperblockCopy.B, volume.ActiveCopy);
        Assert.Equal(2u, volume.Superblock.Sequence);
        Assert.Equal(1, volume.Superblock.Generation);
        Assert.True(volume.Superblock.Clean);
        Assert.Equal(VolumeId, volume.Superblock.VolumeId);
        Assert.Equal("TEST", volume.Superblock.Label);
    }

    [Fact]
    public void SavesAlternateCopiesWithIncreasingSequenceAndGeneration()
    {
        byte[] image = Format360().ToImage();
        List<(uint A, uint B, ushort GenerationA, ushort GenerationB)> history = [];

        for (int session = 0; session < 3; session++)
        {
            Volume volume = Volume.Open(image);
            volume.CreateDirectory($"/s{session}");
            image = volume.ToImage();
            history.Add((
                SequenceIn(image, SuperblockCopy.A),
                SequenceIn(image, SuperblockCopy.B),
                GenerationIn(image, SuperblockCopy.A),
                GenerationIn(image, SuperblockCopy.B)));
        }

        Assert.Equal([(3u, 2u, (ushort)2, (ushort)1), (3u, 4u, (ushort)2, (ushort)3), (5u, 4u, (ushort)4, (ushort)3)], history);
        Assert.Equal(SuperblockCopy.A, Volume.Open(image).ActiveCopy);
        AssertConsistent(Volume.Open(image));
    }

    [Fact]
    public void GenerationBumpsOncePerMutatingSession()
    {
        byte[] image = Format360().ToImage();
        Volume volume = Volume.Open(image);

        volume.CreateDirectory("/a");
        volume.WriteFile("/a/f", Pattern(1000));
        volume.Remove("/a/f");
        byte[] saved = volume.ToImage();

        Assert.Equal(2, Volume.Open(saved).Superblock.Generation);
        Assert.Equal(saved, volume.ToImage());
        volume.WriteFile("/g", [1]);
        Assert.Equal(3, Volume.Open(volume.ToImage()).Superblock.Generation);
        AssertConsistent(volume);
    }

    [Fact]
    public void UnchangedSessionReturnsTheSameBytes()
    {
        Volume formatted = Format360();
        formatted.CreateDirectory("/a");
        byte[] image = formatted.ToImage();
        Volume volume = Volume.Open(image);

        volume.CreateDirectory("/a", createParents: true);
        Assert.Equal(C5fsError.ENOENT, ErrorOf(() => volume.Remove("/missing")));
        Assert.Equal(C5fsError.EISDIR, ErrorOf(() => volume.WriteFile("/a", [])));

        Assert.Equal(image, volume.ToImage());
    }

    [Fact]
    public void CorruptCopyAMeansCopyBWins()
    {
        Volume volume = Volume.Open(Format360().ToImage());
        volume.CreateDirectory("/new");
        byte[] image = volume.ToImage();
        Assert.Equal(SuperblockCopy.A, Volume.Open(image).ActiveCopy);

        image[256 + 100] ^= 0xFF;

        Volume reopened = Volume.Open(image);
        Assert.Equal(SuperblockCopy.B, reopened.ActiveCopy);
        Assert.Equal(2u, reopened.Superblock.Sequence);
        Assert.Equal(1, reopened.Superblock.Generation);
        reopened.WriteFile("/after", [1]);
        byte[] repaired = reopened.ToImage();
        Assert.Equal(3u, SequenceIn(repaired, SuperblockCopy.A));
        Assert.Equal(SuperblockCopy.A, Volume.Open(repaired).ActiveCopy);
        AssertConsistent(reopened);
    }

    [Fact]
    public void HigherSequenceWinsWhenBothCopiesAreValid()
    {
        Volume volume = Volume.Open(Format360().ToImage());
        volume.WriteFile("/f", [1]);
        byte[] image = volume.ToImage();
        volume.WriteFile("/g", [2]);
        byte[] later = volume.ToImage();

        Assert.Equal((SuperblockCopy.A, 3u), (Volume.Open(image).ActiveCopy, Volume.Open(image).Superblock.Sequence));
        Assert.Equal((SuperblockCopy.B, 4u), (Volume.Open(later).ActiveCopy, Volume.Open(later).Superblock.Sequence));
    }

    [Fact]
    public void BadMagicInBothCopiesFailsToOpen()
    {
        byte[] image = Format360().ToImage();
        image[256] = (byte)'X';
        Assert.Equal(SuperblockCopy.B, Volume.Open(image).ActiveCopy);

        image[512 + 254] ^= 0x01;

        C5fsException error = Assert.Throws<C5fsException>(() => Volume.Open(image));
        Assert.Equal(C5fsError.EIO, error.Error);
        Assert.Contains("both superblock copies", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void ImagesOfTheWrongSizeAreRejected()
    {
        byte[] image = Format360().ToImage();

        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => Volume.Open(image.AsSpan(0, 184_320))));
        Assert.Equal(C5fsError.EINVAL, ErrorOf(() => Volume.Open(image.AsSpan(0, 1000))));
        Assert.Equal(C5fsError.EIO, ErrorOf(() => Volume.Open(new byte[184_320])));
    }

    [Fact]
    public void ADirtyVolumeIsSavedClean()
    {
        byte[] image = Format360().ToImage();
        Superblock dirty = Superblock.Parse(Block(image, 2)) with { Clean = false };
        dirty.Serialize().CopyTo(Block(image, 2));
        Volume volume = Volume.Open(image);
        Assert.False(volume.Superblock.Clean);

        volume.WriteFile("/f", [1]);
        byte[] saved = volume.ToImage();

        Assert.Equal(0x01, Block(saved, 1)[5]);
        Assert.True(Volume.Open(saved).Superblock.Clean);
        AssertConsistent(volume);
    }

    [Fact]
    public void SavingRecordsTheLastWrittenTime()
    {
        FixedTimeProvider clock = Clock();
        byte[] image = Format(VolumeGeometry.Floppy180, clock).ToImage();
        clock.Now = clock.Now.AddDays(1);
        Volume volume = Volume.Open(image, clock);

        volume.WriteFile("/f", [1]);

        Superblock saved = Volume.Open(volume.ToImage()).Superblock;
        Assert.Equal(StartSeconds, saved.Created.Seconds);
        Assert.Equal(StartSeconds + 86_400, saved.LastWritten.Seconds);
    }
}
