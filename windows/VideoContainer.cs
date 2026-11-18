using System;
using System.Buffers.Binary;
using System.IO;
using System.Text;

namespace TokMac;

internal static class VideoContainer
{
    internal static string GetExtension(string path)
    {
        using var file = File.OpenRead(path);
        var reader = new Reader(file);
        return reader.IsoFormat() ?? (reader.IsWebM() ? "webm" :
            throw new IOException("无法识别完整的视频文件（支持 MP4、MOV 和 WebM）"));
    }

    private readonly record struct Element(ulong Id, long Start, long End)
    {
        internal long Length => End - Start;
    }

    private sealed class Reader(FileStream file)
    {
        private readonly long length = file.Length;
        private int budget = 20_000;

        private ulong Integer(long offset, int count)
        {
            if (offset < 0 || count > length - offset) throw new EndOfStreamException();
            Span<byte> bytes = stackalloc byte[8];
            bytes.Clear();
            file.Position = offset;
            file.ReadExactly(bytes[(8 - count)..]);
            return BinaryPrimitives.ReadUInt64BigEndian(bytes);
        }

        private Element? Box(long offset, long end)
        {
            if (budget-- <= 0 || end - offset < 8) return null;
            ulong size = Integer(offset, 4);
            ulong type = Integer(offset + 4, 4);
            int header = size == 1 ? 16 : 8;
            if (end - offset < header) return null;
            if (size == 1) size = Integer(offset + 8, 8);
            else if (size == 0) size = (ulong)(end - offset);
            if (size < (ulong)header || size > (ulong)(end - offset)) return null;
            return new(type, offset + header, offset + (long)size);
        }

        private bool HasIsoVideoTrack(Element parent, ReadOnlySpan<uint> ancestors)
        {
            for (long offset = parent.Start; offset < parent.End;)
            {
                if (Box(offset, parent.End) is not { } box) return false;
                if (!ancestors.IsEmpty)
                {
                    if (box.Id == ancestors[0] && HasIsoVideoTrack(box, ancestors[1..])) return true;
                }
                else if (box.Id == 0x68646c72 && box.Length >= 12 && Integer(box.Start + 8, 4) == 0x76696465) // hdlr: vide
                    return true;
                offset = box.End;
            }
            return false;
        }

        internal string? IsoFormat()
        {
            string? format = null;
            bool videoTrack = false, mediaData = false;
            Span<byte> brand = stackalloc byte[4];
            for (long offset = 0; offset < length;)
            {
                if (Box(offset, length) is not { } box) return null;
                switch (box.Id)
                {
                    case 0x66747970: // ftyp
                        if (format != null || box.Length < 8) return null;
                        BinaryPrimitives.WriteUInt32BigEndian(brand, (uint)Integer(box.Start, 4));
                        format = Encoding.ASCII.GetString(brand) switch
                        {
                            "qt  " => "mov",
                            "isom" or "iso2" or "iso3" or "iso4" or "iso5" or "iso6" or "iso7" or "iso8" or "iso9" or
                            "mp41" or "mp42" or "avc1" or "hvc1" or "hev1" or "M4V " or "dash" or "MSNV" => "mp4",
                            _ => null,
                        };
                        if (format == null) return null;
                        break;
                    case 0x6d6f6f76: // moov
                        videoTrack = HasIsoVideoTrack(box, [0x7472616b, 0x6d646961]); // trak, mdia
                        break;
                    case 0x6d646174: // mdat
                        mediaData |= box.Length > 0;
                        break;
                }
                offset = box.End;
            }
            return videoTrack && mediaData ? format ?? "mov" : null;
        }

        private (ulong Value, int Width, bool Unknown)? Vint(long offset, long end, bool isId)
        {
            if (offset >= end) return null;
            ulong first = Integer(offset, 1);
            if (first == 0) return null;
            int width = System.Numerics.BitOperations.LeadingZeroCount(first) - 55;
            if (width > (isId ? 4 : 8) || width > end - offset) return null;
            ulong encoded = Integer(offset, width);
            ulong mask = (1UL << (7 * width)) - 1;
            ulong value = isId ? encoded : encoded & mask;
            return (value, width, !isId && value == mask);
        }

        private Element? Ebml(long offset, long end)
        {
            if (budget-- <= 0 || Vint(offset, end, true) is not { } id ||
                Vint(offset + id.Width, end, false) is not { } size) return null;
            long start = offset + id.Width + size.Width;
            // WebM permits unknown lengths for streaming Segment and Cluster elements.
            if (size.Unknown && id.Value is not (0x18538067 or 0x1f43b675)) return null;
            ulong count = size.Unknown ? (ulong)(end - start) : size.Value;
            return count <= (ulong)(end - start) ? new(id.Value, start, start + (long)count) : null;
        }

        private bool HasWebMVideoTrack(Element tracks)
        {
            for (long offset = tracks.Start; offset < tracks.End;)
            {
                if (Ebml(offset, tracks.End) is not { } entry) return false;
                if (entry.Id == 0xae)
                {
                    for (long fieldOffset = entry.Start; fieldOffset < entry.End;)
                    {
                        if (Ebml(fieldOffset, entry.End) is not { } field) return false;
                        if (field.Id == 0x83 && field.Length is >= 1 and <= 8 && Integer(field.Start, (int)field.Length) == 1)
                            return true;
                        fieldOffset = field.End;
                    }
                }
                offset = entry.End;
            }
            return false;
        }

        internal bool IsWebM()
        {
            if (Ebml(0, length) is not { Id: 0x1a45dfa3 } header) return false;
            bool webm = false;
            for (long offset = header.Start; offset < header.End;)
            {
                if (Ebml(offset, header.End) is not { } field) return false;
                if (field.Id == 0x4282 && field.Length == 4) webm = Integer(field.Start, 4) == 0x7765626d; // webm
                offset = field.End;
            }
            if (!webm || Ebml(header.End, length) is not { Id: 0x18538067 } segment || segment.End != length) return false;
            bool videoTrack = false, cluster = false;
            for (long offset = segment.Start; offset < length;)
            {
                if (Ebml(offset, length) is not { } item) return false;
                if (item.Id == 0x1654ae6b) videoTrack = HasWebMVideoTrack(item);
                if (item.Id == 0x1f43b675) cluster |= item.Length > 0;
                offset = item.End;
            }
            return videoTrack && cluster;
        }
    }
}
