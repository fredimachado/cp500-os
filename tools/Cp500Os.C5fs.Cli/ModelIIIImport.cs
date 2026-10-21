using System.Buffers.Binary;
using System.Text;
using Cp500Os.C5fs;
using Heh8080.Devices;

namespace Cp500Os.C5fs.Cli;

internal static class ModelIIIImport
{
    private const int DirectoryTrack = 17;

    public static void Import(Volume volume, ModelIIIDiskImage disk, TimeProvider time)
    {
        DirectoryTrackLayout layout = ReadDirectoryTrack(disk);
        C5Time importTime = C5Time.Now(time);
        foreach (ImportedFile file in CollectFiles(disk, layout, importTime))
        {
            string path = $"/{file.Name.Value}";
            try
            {
                volume.Stat(path);
                throw new C5fsException(C5fsError.EEXIST, $"'{path}' already exists");
            }
            catch (C5fsException e) when (e.Error == C5fsError.ENOENT)
            {
            }

            volume.WriteFile(path, file.Content, file.Created, file.Modified);
        }
    }

    public static void ImportFromFile(Volume volume, string sourcePath, TimeProvider time)
    {
        byte[] bytes = File.ReadAllBytes(sourcePath);
        ModelIIIDiskImageKind kind = ModelIIIDiskCodec.DetectKind(sourcePath, bytes.Length);
        ModelIIIDiskImage disk = ModelIIIDiskCodec.Parse(bytes, kind);
        Import(volume, disk, time);
    }

    private readonly record struct ImportedFile(FileName Name, byte[] Content, C5Time Created, C5Time Modified);

    private enum DiskLayoutKind
    {
        Trsdos13,
        Ldos5,
    }

    private sealed class DirectoryTrackLayout
    {
        public required DiskLayoutKind Kind { get; init; }

        public required ReadOnlyMemory<byte> Gat { get; init; }

        public required ReadOnlyMemory<byte> Hit { get; init; }

        public required ReadOnlyMemory<byte>[] DirectorySectors { get; init; }

        public required int GranulesPerCylinder { get; init; }

        public required int SectorsPerGranule { get; init; }

        public int RecordSize => Kind == DiskLayoutKind.Trsdos13 ? 48 : 32;

        public int RecordsPerSector => Kind == DiskLayoutKind.Trsdos13 ? 5 : 8;
    }

    private static DirectoryTrackLayout ReadDirectoryTrack(ModelIIIDiskImage disk)
    {
        for (int id = 1; id <= ModelIIIDiskGeometry.SectorsPerTrack; id++)
        {
            if (disk.FindSector(DirectoryTrack, 0, id) is null)
            {
                throw new C5fsException(C5fsError.EIO, $"directory track is missing sector id {id}");
            }
        }

        ModelIIIDiskSector[] sorted = disk.GetTrack(DirectoryTrack, 0).OrderBy(sector => sector.Id).ToArray();
        ReadOnlyMemory<byte> gat = sorted[0].Data;
        ReadOnlyMemory<byte> hit = sorted[1].Data;
        ReadOnlyMemory<byte>[] directorySectors = sorted.Skip(2).Select(sector => (ReadOnlyMemory<byte>)sector.Data).ToArray();
        if (directorySectors.Length == 0)
        {
            throw new C5fsException(C5fsError.EIO, "directory track has no directory sectors");
        }

        DiskLayoutKind kind = DetectLayout(gat.Span, directorySectors[0].Span);
        int granulesPerCylinder = kind switch
        {
            DiskLayoutKind.Trsdos13 => 6,
            DiskLayoutKind.Ldos5 => (gat.Span[0xCD] & 7) + 1,
            _ => throw new InvalidOperationException("Unknown disk layout."),
        };
        if (ModelIIIDiskGeometry.SectorsPerTrack % granulesPerCylinder != 0)
        {
            throw new C5fsException(C5fsError.EIO, "LDOS granule geometry does not divide the track");
        }

        return new DirectoryTrackLayout
        {
            Kind = kind,
            Gat = gat,
            Hit = hit,
            DirectorySectors = directorySectors,
            GranulesPerCylinder = granulesPerCylinder,
            SectorsPerGranule = ModelIIIDiskGeometry.SectorsPerTrack / granulesPerCylinder,
        };
    }

    private static DiskLayoutKind DetectLayout(ReadOnlySpan<byte> gat, ReadOnlySpan<byte> firstDirectory)
    {
        if (LooksLikeLdos(gat, firstDirectory))
        {
            return DiskLayoutKind.Ldos5;
        }

        if (gat.Length >= 40 && IsTrsdosGat(gat))
        {
            return DiskLayoutKind.Trsdos13;
        }

        throw new C5fsException(C5fsError.EIO, "unrecognized Model III directory format");
    }

    // LDOS keeps granules-per-cylinder in GAT[CDh] and ends a record with FFh or FEh.
    // TRSDOS 1.3 leaves those GAT bits clear and does not use that link byte, so the
    // granule map alone cannot tell the two apart.
    private static bool LooksLikeLdos(ReadOnlySpan<byte> gat, ReadOnlySpan<byte> directory)
    {
        if (gat.Length <= 0xCD || directory.Length < 32)
        {
            return false;
        }

        int granulesPerCylinder = (gat[0xCD] & 7) + 1;
        if (granulesPerCylinder <= 1 || ModelIIIDiskGeometry.SectorsPerTrack % granulesPerCylinder != 0)
        {
            return false;
        }

        for (int slot = 0; slot < 8 && ((slot * 32) + 32) <= directory.Length; slot++)
        {
            ReadOnlySpan<byte> record = directory.Slice(slot * 32, 32);
            if ((record[0] & 0x10) != 0 && record[30] is 0xFE or 0xFF)
            {
                return true;
            }
        }

        return false;
    }

    private static bool IsTrsdosGat(ReadOnlySpan<byte> gat)
    {
        for (int i = 0; i < 40; i++)
        {
            if ((gat[i] & 0xC0) != 0)
            {
                return false;
            }
        }

        return true;
    }

    private static List<ImportedFile> CollectFiles(ModelIIIDiskImage disk, DirectoryTrackLayout layout, C5Time importTime)
    {
        List<ImportedFile> files = [];
        for (int sectorIndex = 0; sectorIndex < layout.DirectorySectors.Length; sectorIndex++)
        {
            ReadOnlySpan<byte> sector = layout.DirectorySectors[sectorIndex].Span;
            for (int slot = 0; slot < layout.RecordsPerSector; slot++)
            {
                int offset = slot * layout.RecordSize;
                ReadOnlySpan<byte> record = sector.Slice(offset, layout.RecordSize);
                if (!IsAssignedPrimary(layout.Kind, record))
                {
                    continue;
                }

                files.Add(TryReadPrimaryFile(disk, layout, record, sectorIndex, slot, importTime));
            }
        }

        if (layout.Kind == DiskLayoutKind.Trsdos13)
        {
            files.AddRange(ReadTrsdosSystemFiles(disk, layout, importTime));
        }

        return files;
    }

    private static bool IsAssignedPrimary(DiskLayoutKind kind, ReadOnlySpan<byte> record) =>
        kind switch
        {
            DiskLayoutKind.Trsdos13 => (record[0] & 0x10) != 0 && (record[0] & 0x80) == 0,
            DiskLayoutKind.Ldos5 => (record[0] & 0x10) != 0 && (record[0] & 0x80) == 0,
            _ => false,
        };

    private static ImportedFile TryReadPrimaryFile(
        ModelIIIDiskImage disk,
        DirectoryTrackLayout layout,
        ReadOnlySpan<byte> record,
        int sectorIndex,
        int slot,
        C5Time importTime)
    {
        FileName name = ParseDosName(record);
        (C5Time created, C5Time modified) = layout.Kind switch
        {
            DiskLayoutKind.Trsdos13 => TrsdosTimestamps(record, importTime),
            DiskLayoutKind.Ldos5 => LdosTimestamps(record, importTime),
            _ => (importTime, importTime),
        };
        int logicalLength = layout.Kind switch
        {
            DiskLayoutKind.Trsdos13 => TrsdosLogicalLength(record),
            DiskLayoutKind.Ldos5 => LdosLogicalLength(record),
            _ => 0,
        };
        List<GranuleExtent> extents = layout.Kind switch
        {
            DiskLayoutKind.Trsdos13 => ReadTrsdosExtents(record),
            DiskLayoutKind.Ldos5 => ReadLdosExtentChain(layout, record, sectorIndex, slot),
            _ => [],
        };
        byte[] content = ReadPayload(disk, layout, extents, logicalLength);
        return new ImportedFile(name, content, created, modified);
    }

    private static List<ImportedFile> ReadTrsdosSystemFiles(ModelIIIDiskImage disk, DirectoryTrackLayout layout, C5Time importTime)
    {
        List<ImportedFile> files = [];
        ReadOnlySpan<byte> hit = layout.Hit.Span;
        for (int index = 0; index < 15; index++)
        {
            int offset = 0xE0 + (index * 2);
            byte granuleByte = hit[offset];
            byte track = hit[offset + 1];
            if (track == 0xFF && granuleByte == 0xFF)
            {
                continue;
            }

            int startGranule = (granuleByte >> 5) & 7;
            int count = granuleByte & 0x1F;
            if (count == 0)
            {
                continue;
            }

            FileName name = FileName.Parse($"SYS{index}.SYS");
            List<GranuleExtent> extents = [new GranuleExtent(track, startGranule, count)];
            byte[] content = ReadPayload(disk, layout, extents, int.MaxValue);
            files.Add(new ImportedFile(name, content, importTime, importTime));
        }

        return files;
    }

    private readonly record struct GranuleExtent(byte Track, int StartGranule, int Count);

    private static List<GranuleExtent> ReadTrsdosExtents(ReadOnlySpan<byte> record)
    {
        List<GranuleExtent> extents = [];
        for (int pair = 0; pair < 13; pair++)
        {
            int offset = 22 + (pair * 2);
            byte track = record[offset];
            byte granuleByte = record[offset + 1];
            if (track is 0xFE or 0xFF || granuleByte == 0)
            {
                break;
            }

            int start = (granuleByte >> 5) & 7;
            int count = granuleByte & 0x1F;
            if (count == 0)
            {
                break;
            }

            extents.Add(new GranuleExtent(track, start, count));
        }

        return extents;
    }

    private static List<GranuleExtent> ReadLdosExtentChain(
        DirectoryTrackLayout layout,
        ReadOnlySpan<byte> primary,
        int sectorIndex,
        int slot)
    {
        List<GranuleExtent> extents = [];
        ReadOnlySpan<byte> record = primary;
        int currentSectorIndex = sectorIndex;
        int currentSlot = slot;
        while (true)
        {
            AddLdosRecordExtents(record, extents);
            byte link = record[30];
            if (link == 0xFF)
            {
                break;
            }

            if (link != 0xFE)
            {
                throw new C5fsException(C5fsError.EIO, "invalid LDOS directory extension link");
            }

            byte dec = record[31];
            (currentSectorIndex, currentSlot) = ResolveDec(layout, dec);
            record = GetRecord(layout, currentSectorIndex, currentSlot);
            if ((record[0] & 0x80) == 0)
            {
                throw new C5fsException(C5fsError.EIO, "LDOS extension record is not marked extended");
            }
        }

        return extents;
    }

    private static void AddLdosRecordExtents(ReadOnlySpan<byte> record, List<GranuleExtent> extents)
    {
        for (int pair = 0; pair < 4; pair++)
        {
            int offset = 22 + (pair * 2);
            byte track = record[offset];
            byte granuleByte = record[offset + 1];
            if (track is 0xFE or 0xFF || granuleByte == 0)
            {
                break;
            }

            int start = (granuleByte >> 5) & 7;
            int count = granuleByte & 0x1F;
            if (count == 0)
            {
                break;
            }

            extents.Add(new GranuleExtent(track, start, count));
        }
    }

    private static (int SectorIndex, int Slot) ResolveDec(DirectoryTrackLayout layout, byte dec)
    {
        int sectorIndex = dec & 31;
        int slot = dec >> 5;
        if (sectorIndex >= layout.DirectorySectors.Length || slot >= layout.RecordsPerSector)
        {
            throw new C5fsException(C5fsError.EIO, "LDOS DEC points outside the directory");
        }

        return (sectorIndex, slot);
    }

    private static ReadOnlySpan<byte> GetRecord(DirectoryTrackLayout layout, int sectorIndex, int slot) =>
        layout.DirectorySectors[sectorIndex].Span.Slice(slot * layout.RecordSize, layout.RecordSize);

    private static byte[] ReadPayload(
        ModelIIIDiskImage disk,
        DirectoryTrackLayout layout,
        IReadOnlyList<GranuleExtent> extents,
        int logicalLength)
    {
        int capacity = 0;
        foreach (GranuleExtent extent in extents)
        {
            capacity += extent.Count * layout.SectorsPerGranule * ModelIIIDiskGeometry.BytesPerSector;
        }

        byte[] buffer = capacity == 0 ? [] : new byte[capacity];
        int written = 0;
        ReadOnlySpan<byte> gat = layout.Gat.Span;
        foreach (GranuleExtent extent in extents)
        {
            for (int granule = 0; granule < extent.Count; granule++)
            {
                int granuleIndex = extent.StartGranule + granule;
                if (!IsGranuleAllocated(gat, extent.Track, granuleIndex))
                {
                    throw new C5fsException(C5fsError.EIO, $"granule {granuleIndex} on track {extent.Track} is not allocated");
                }

                for (int sectorOffset = 0; sectorOffset < layout.SectorsPerGranule; sectorOffset++)
                {
                    int sectorId = (granuleIndex * layout.SectorsPerGranule) + sectorOffset + 1;
                    ModelIIIDiskSector? sector = disk.FindSector(extent.Track, 0, sectorId)
                        ?? throw new C5fsException(C5fsError.EIO, $"missing sector T{extent.Track} id {sectorId}");
                    int copy = Math.Min(ModelIIIDiskGeometry.BytesPerSector, buffer.Length - written);
                    if (copy <= 0)
                    {
                        break;
                    }

                    sector.Data.AsSpan(0, copy).CopyTo(buffer.AsSpan(written));
                    written += ModelIIIDiskGeometry.BytesPerSector;
                }
            }
        }

        int length = Math.Min(logicalLength, written);
        if (length == buffer.Length)
        {
            return buffer;
        }

        return buffer.AsSpan(0, length).ToArray();
    }

    private static bool IsGranuleAllocated(ReadOnlySpan<byte> gat, int track, int granule)
    {
        if (track < 0 || track >= gat.Length || granule is < 0 or > 7)
        {
            return false;
        }

        return (gat[track] & (1 << granule)) != 0;
    }

    private static int TrsdosLogicalLength(ReadOnlySpan<byte> record)
    {
        int eof = record[3];
        int sectors = BinaryPrimitives.ReadUInt16LittleEndian(record[20..]);
        return eof == 0 ? sectors * 256 : ((sectors - 1) * 256) + eof;
    }

    private static int LdosLogicalLength(ReadOnlySpan<byte> record)
    {
        int eof = record[3];
        int endingRecord = BinaryPrimitives.ReadUInt16LittleEndian(record[20..]);
        return (endingRecord * 256) + eof;
    }

    private static (C5Time Created, C5Time Modified) TrsdosTimestamps(ReadOnlySpan<byte> record, C5Time importTime)
    {
        int month = record[1];
        int year = 1900 + record[2];
        if (month is >= 1 and <= 12 && year is >= 1980 and <= 2099)
        {
            C5Time time = C5Time.FromDateTime(new DateTime(year, month, 1, 0, 0, 0, DateTimeKind.Unspecified));
            return (time, time);
        }

        return (importTime, importTime);
    }

    private static (C5Time Created, C5Time Modified) LdosTimestamps(ReadOnlySpan<byte> record, C5Time importTime)
    {
        if ((record[1] & 0x10) != 0)
        {
            return (importTime, importTime);
        }

        int month = record[1] & 0x0F;
        int day = (record[2] >> 3) & 0x1F;
        int year = 1980 + (record[2] & 7);
        if (month is >= 1 and <= 12 && day is >= 1 and <= 31)
        {
            try
            {
                C5Time time = C5Time.FromDateTime(new DateTime(year, month, day, 0, 0, 0, DateTimeKind.Unspecified));
                return (time, time);
            }
            catch (ArgumentOutOfRangeException)
            {
                return (importTime, importTime);
            }
        }

        return (importTime, importTime);
    }

    private static FileName ParseDosName(ReadOnlySpan<byte> record)
    {
        string name = TrimDosField(record.Slice(5, 8));
        string extension = TrimDosField(record.Slice(13, 3));
        string full = extension.Length == 0 ? name : $"{name}.{extension}";
        return FileName.Parse(full);
    }

    private static string TrimDosField(ReadOnlySpan<byte> field)
    {
        int end = field.Length;
        while (end > 0 && field[end - 1] is (byte)' ' or 0)
        {
            end--;
        }

        return Encoding.ASCII.GetString(field[..end]);
    }
}
