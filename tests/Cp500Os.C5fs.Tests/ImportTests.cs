using System.Buffers.Binary;
using System.Text;
using Cp500Os.C5fs.Cli;
using Heh8080.Devices;
using static Cp500Os.C5fs.Tests.TestSupport;

namespace Cp500Os.C5fs.Tests;

public sealed class ImportTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("c5fs-import-").FullName;

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    [Fact]
    public void TrsdosJv3ImportsFilesWithTimestampsAndRejectsDuplicates()
    {
        const int DataTrack = 20;
        ModelIIIDiskImage disk = ModelIIIDiskImage.CreateBlank(ModelIIIDiskFormat.SingleSided);
        WriteTrsdosGat(disk, DataTrack);
        WriteTrsdosDirectoryRecord(disk, "NOTE", "TXT", month: 5, yearByte: 81, sectors: 1, eof: 5, DataTrack, startGranule: 0, count: 1);
        WriteSectorPayload(disk, DataTrack, 1, "hello"u8);

        string source = PathOf("note.jv3");
        File.WriteAllBytes(source, ModelIIIDiskCodec.Serialize(disk, ModelIIIDiskImageKind.Jv3));

        string image = PathOf("c5fs.img");
        File.WriteAllBytes(image, Format360().ToImage());
        Assert.Equal(0, Run("import", source, image).Exit);

        Volume volume = Volume.Open(File.ReadAllBytes(image));
        Assert.Equal("hello"u8.ToArray(), volume.ReadFile("/NOTE.TXT"));
        C5Time expected = C5Time.FromDateTime(new DateTime(1981, 5, 1, 0, 0, 0, DateTimeKind.Unspecified));
        FileStatus status = volume.Stat("/NOTE.TXT");
        Assert.Equal(expected, status.Inode.Created);
        Assert.Equal(expected, status.Inode.Modified);

        Assert.Equal((1, "", Lines("c5fs: EEXIST: '/NOTE.TXT' already exists")), Run("import", source, image));
    }

    [Fact]
    public void LdosDmkImportsFilesWithTimestamps()
    {
        const int DataTrack = 21;
        ModelIIIDiskImage disk = ModelIIIDiskImage.CreateBlank(ModelIIIDiskFormat.SingleSided);
        WriteLdosGat(disk, DataTrack);
        WriteLdosDirectoryRecord(disk, "MEMO", "DAT", month: 5, day: 15, yearSince1980: 4, eof: 4, endingRecord: 0, DataTrack, startGranule: 0, count: 1);
        WriteSectorPayload(disk, DataTrack, 1, "memo"u8);

        string source = PathOf("memo.dmk");
        File.WriteAllBytes(source, ModelIIIDiskCodec.Serialize(disk, ModelIIIDiskImageKind.Dmk));

        string image = PathOf("c5fs.img");
        File.WriteAllBytes(image, Format360().ToImage());
        Assert.Equal(0, Run("import", source, image).Exit);

        Volume volume = Volume.Open(File.ReadAllBytes(image));
        Assert.Equal("memo"u8.ToArray(), volume.ReadFile("/MEMO.DAT"));
        C5Time expected = C5Time.FromDateTime(new DateTime(1984, 5, 15, 0, 0, 0, DateTimeKind.Unspecified));
        FileStatus status = volume.Stat("/MEMO.DAT");
        Assert.Equal(expected, status.Inode.Created);
        Assert.Equal(expected, status.Inode.Modified);
    }

    private static void WriteTrsdosGat(ModelIIIDiskImage disk, int dataTrack)
    {
        byte[] gat = new byte[256];
        gat[dataTrack] = 0x01;
        disk.WriteSector(DirectoryTrack, 0, GatSectorId, gat, deletedData: false);

        byte[] hit = new byte[256];
        for (int offset = 0xE0; offset <= 0xFD; offset += 2)
        {
            hit[offset] = 0xFF;
            hit[offset + 1] = 0xFF;
        }

        disk.WriteSector(DirectoryTrack, 0, HitSectorId, hit, deletedData: false);
    }

    private static void WriteLdosGat(ModelIIIDiskImage disk, int dataTrack)
    {
        byte[] gat = new byte[256];
        gat[0xCD] = 5;
        gat[dataTrack] = 0x01;
        disk.WriteSector(DirectoryTrack, 0, GatSectorId, gat, deletedData: false);
    }

    private static void WriteTrsdosDirectoryRecord(
        ModelIIIDiskImage disk,
        string name,
        string extension,
        int month,
        int yearByte,
        int sectors,
        int eof,
        int track,
        int startGranule,
        int count)
    {
        byte[] sector = new byte[256];
        Span<byte> record = sector.AsSpan(0, 48);
        record[0] = 0x10;
        record[1] = (byte)month;
        record[2] = (byte)yearByte;
        record[3] = (byte)eof;
        WriteDosField(record.Slice(5, 8), name);
        WriteDosField(record.Slice(13, 3), extension);
        BinaryPrimitives.WriteUInt16LittleEndian(record.Slice(20, 2), (ushort)sectors);
        record[22] = (byte)track;
        record[23] = (byte)((startGranule << 5) | (count & 0x1F));
        disk.WriteSector(DirectoryTrack, 0, FirstDirectorySectorId, sector, deletedData: false);
    }

    private static void WriteLdosDirectoryRecord(
        ModelIIIDiskImage disk,
        string name,
        string extension,
        int month,
        int day,
        int yearSince1980,
        int eof,
        int endingRecord,
        int track,
        int startGranule,
        int count)
    {
        byte[] sector = new byte[256];
        Span<byte> record = sector.AsSpan(0, 32);
        record[0] = 0x10;
        record[1] = (byte)month;
        record[2] = (byte)((day << 3) | (yearSince1980 & 7));
        record[3] = (byte)eof;
        WriteDosField(record.Slice(5, 8), name);
        WriteDosField(record.Slice(13, 3), extension);
        BinaryPrimitives.WriteUInt16LittleEndian(record.Slice(20, 2), (ushort)endingRecord);
        record[22] = (byte)track;
        record[23] = (byte)((startGranule << 5) | (count & 0x1F));
        record[30] = 0xFF;
        disk.WriteSector(DirectoryTrack, 0, FirstDirectorySectorId, sector, deletedData: false);
    }

    private static void WriteSectorPayload(ModelIIIDiskImage disk, int track, int sectorId, ReadOnlySpan<byte> payload)
    {
        byte[] sector = new byte[256];
        Array.Fill(sector, (byte)0xE5);
        payload.CopyTo(sector);
        disk.WriteSector(track, 0, sectorId, sector, deletedData: false);
    }

    private static void WriteDosField(Span<byte> field, string text)
    {
        field.Fill((byte)' ');
        Encoding.ASCII.GetBytes(text, field);
    }

    private const int DirectoryTrack = 17;

    private const int GatSectorId = 1;

    private const int HitSectorId = 2;

    private const int FirstDirectorySectorId = 3;

    private string PathOf(string name) => Path.Combine(_directory, name);

    private static string Lines(params string[] lines) => string.Concat(lines.Select(line => line + Environment.NewLine));

    private static (int Exit, string Output, string Error) Run(params string[] args)
    {
        using StringWriter output = new();
        using StringWriter error = new();
        int exit = C5fsCli.Run(args, output, error, Clock());
        return (exit, output.ToString(), error.ToString());
    }
}
