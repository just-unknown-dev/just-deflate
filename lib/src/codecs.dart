/// The raw DEFLATE, zlib and gzip formats.
library;

import 'dart:typed_data';

import 'checksum.dart';
import 'deflater.dart';
import 'inflater.dart';

/// Raw DEFLATE streams (RFC 1951): no header, no checksum.
///
/// Stateless; one instance can be shared.
///
/// ```dart
/// const deflate = DeflateCodec();
/// final packed = deflate.encode(bytes);
/// final unpacked = deflate.decode(packed);
/// ```
class DeflateCodec {
  /// A codec that compresses at [level], from 0 (stored, no compression)
  /// to 9 (smallest output, slowest). 6 is zlib's default balance.
  const DeflateCodec({this.level = 6});

  /// The compression level [encode] uses, 0-9.
  final int level;

  /// [data] compressed as one raw DEFLATE stream.
  ///
  /// Throws [RangeError] if [level] is not 0-9.
  Uint8List encode(List<int> data) {
    _checkLevel(level);
    final input = _asBytes(data);
    return (Deflater(
      sizeHint: _encodeHint(input),
    )..deflate(input, level)).takeBytes();
  }

  /// The bytes of the raw DEFLATE stream at the start of [data]. Bytes
  /// after the stream are ignored.
  ///
  /// Throws [FormatException] if [data] is not valid DEFLATE data, or would
  /// decode to more than [maxOutputSize] bytes.
  Uint8List decode(List<int> data, {int? maxOutputSize}) {
    final input = _asBytes(data);
    final inflater = Inflater(
      maxOutputSize: maxOutputSize,
      sizeHint: _decodeHint(input),
    );
    inflater.inflate(input, 0);
    return inflater.takeBytes();
  }
}

/// zlib streams (RFC 1950): a two-byte header, a DEFLATE stream and an
/// Adler-32 checksum. Tiled's default layer compression, and what PNG
/// stores its pixels in.
///
/// Stateless; one instance can be shared.
///
/// ```dart
/// const zlib = ZlibCodec();
/// final packed = zlib.encode(bytes);
/// final unpacked = zlib.decode(packed);
/// ```
class ZlibCodec {
  /// A codec that compresses at [level], from 0 (stored, no compression)
  /// to 9 (smallest output, slowest). 6 is zlib's default balance.
  const ZlibCodec({this.level = 6});

  /// The compression level [encode] uses, 0-9.
  final int level;

  /// [data] compressed as a zlib stream.
  ///
  /// Throws [RangeError] if [level] is not 0-9.
  Uint8List encode(List<int> data) {
    _checkLevel(level);
    final input = _asBytes(data);
    // FLEVEL is informational: 0 fastest, 1 fast, 2 default, 3 smallest.
    final flevel = level < 2
        ? 0
        : level < 6
        ? 1
        : level == 6
        ? 2
        : 3;
    var header = 0x7800 | (flevel << 6);
    header += 31 - header % 31;
    final adler = adler32(input);
    return (Deflater(sizeHint: _encodeHint(input))
          ..addBytes([header >> 8, header & 0xFF])
          ..deflate(input, level)
          ..addBytes([
            (adler >>> 24) & 0xFF,
            (adler >>> 16) & 0xFF,
            (adler >>> 8) & 0xFF,
            adler & 0xFF,
          ]))
        .takeBytes();
  }

  /// The bytes of the zlib stream at the start of [data]. Bytes after the
  /// stream are ignored.
  ///
  /// Throws [FormatException] if [data] is not a valid zlib stream — the
  /// checksum included — uses a preset dictionary, or would decode to more
  /// than [maxOutputSize] bytes.
  Uint8List decode(List<int> data, {int? maxOutputSize}) {
    final input = _asBytes(data);
    if (input.length < 2) {
      throw const FormatException('zlib: truncated header');
    }
    final cmf = input[0], flg = input[1];
    if (cmf & 0x0F != 8) {
      throw const FormatException('zlib: unknown compression method');
    }
    if (cmf >> 4 > 7) {
      throw const FormatException('zlib: invalid window size');
    }
    if (((cmf << 8) | flg) % 31 != 0) {
      throw const FormatException('zlib: incorrect header check');
    }
    if (flg & 0x20 != 0) {
      throw const FormatException(
        'zlib: preset dictionaries are not supported',
      );
    }
    final inflater = Inflater(
      maxOutputSize: maxOutputSize,
      sizeHint: _decodeHint(input),
    );
    final end = inflater.inflate(input, 2);
    if (input.length - end < 4) {
      throw const FormatException('zlib: truncated checksum');
    }
    final expected = ByteData.sublistView(input).getUint32(end, Endian.big);
    if (adler32(inflater.view()) != expected) {
      throw const FormatException('zlib: incorrect data check');
    }
    return inflater.takeBytes();
  }
}

/// gzip files (RFC 1952): a header, a DEFLATE stream, then the CRC-32 and
/// size of the data. Several members in a row decode as one.
///
/// Stateless; one instance can be shared.
///
/// ```dart
/// const gzip = GzipCodec();
/// final packed = gzip.encode(bytes);
/// final unpacked = gzip.decode(packed);
/// ```
class GzipCodec {
  /// A codec that compresses at [level], from 0 (stored, no compression)
  /// to 9 (smallest output, slowest). 6 is zlib's default balance.
  const GzipCodec({this.level = 6});

  /// The compression level [encode] uses, 0-9.
  final int level;

  /// [data] compressed as a gzip member with no name, comment or time, so
  /// the same data always gives the same bytes.
  ///
  /// Throws [RangeError] if [level] is not 0-9.
  Uint8List encode(List<int> data) {
    _checkLevel(level);
    final input = _asBytes(data);
    // XFL: 2 = smallest, 4 = fastest. OS 255 = unknown.
    final xfl = level == 9
        ? 2
        : level < 2
        ? 4
        : 0;
    final crc = crc32(input);
    final size = input.length;
    return (Deflater(sizeHint: _encodeHint(input))
          ..addBytes([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, xfl, 255])
          ..deflate(input, level)
          ..addBytes([..._uint32le(crc), ..._uint32le(size)]))
        .takeBytes();
  }

  /// The bytes of the gzip data in [data]: every member, one after another.
  /// Bytes after the last member that do not start another are ignored.
  ///
  /// Throws [FormatException] if [data] is not valid gzip data — each
  /// member's CRC-32 and size included — or would decode to more than
  /// [maxOutputSize] bytes.
  Uint8List decode(List<int> data, {int? maxOutputSize}) {
    final input = _asBytes(data);
    final view = ByteData.sublistView(input);
    // A one-member file ends with its size, the best first guess there is.
    var hint = 0;
    if (input.length >= 18) {
      hint = view.getUint32(input.length - 4, Endian.little);
      if (hint > input.length * 1032) hint = 0;
    }
    final inflater = Inflater(maxOutputSize: maxOutputSize, sizeHint: hint);
    var pos = 0;
    do {
      pos = _header(input, pos);
      final start = inflater.length;
      pos = inflater.inflate(input, pos);
      if (input.length - pos < 8) {
        throw const FormatException('gzip: truncated trailer');
      }
      if (crc32(inflater.view(start)) != view.getUint32(pos, Endian.little)) {
        throw const FormatException('gzip: incorrect data check');
      }
      final size = (inflater.length - start) & 0xFFFFFFFF;
      if (size != view.getUint32(pos + 4, Endian.little)) {
        throw const FormatException('gzip: incorrect length check');
      }
      pos += 8;
    } while (input.length - pos >= 2 &&
        input[pos] == 0x1F &&
        input[pos + 1] == 0x8B);
    return inflater.takeBytes();
  }

  /// Reads the member header at [pos]; returns where its DEFLATE data starts.
  static int _header(Uint8List input, int pos) {
    final start = pos;
    if (input.length - pos < 10) {
      throw const FormatException('gzip: truncated header');
    }
    if (input[pos] != 0x1F || input[pos + 1] != 0x8B) {
      throw const FormatException('gzip: not gzip data');
    }
    if (input[pos + 2] != 8) {
      throw const FormatException('gzip: unknown compression method');
    }
    final flags = input[pos + 3];
    if (flags & 0xE0 != 0) {
      throw const FormatException('gzip: reserved flag bits set');
    }
    pos += 10;
    if (flags & 0x04 != 0) {
      // FEXTRA: a two-byte length, then that many bytes.
      if (input.length - pos < 2) {
        throw const FormatException('gzip: truncated header');
      }
      pos += 2 + (input[pos] | (input[pos + 1] << 8));
    }
    if (flags & 0x08 != 0) pos = _skipString(input, pos); // FNAME
    if (flags & 0x10 != 0) pos = _skipString(input, pos); // FCOMMENT
    if (flags & 0x02 != 0) {
      // FHCRC: the low 16 bits of the CRC-32 of the header so far.
      if (input.length - pos < 2) {
        throw const FormatException('gzip: truncated header');
      }
      final crc = crc32(Uint8List.sublistView(input, start, pos)) & 0xFFFF;
      if (crc != (input[pos] | (input[pos + 1] << 8))) {
        throw const FormatException('gzip: incorrect header check');
      }
      pos += 2;
    }
    if (pos > input.length) {
      throw const FormatException('gzip: truncated header');
    }
    return pos;
  }

  /// The offset after the zero that ends the string at [pos].
  static int _skipString(Uint8List input, int pos) {
    while (pos < input.length && input[pos] != 0) {
      pos++;
    }
    if (pos >= input.length) {
      throw const FormatException('gzip: truncated header');
    }
    return pos + 1;
  }
}

List<int> _uint32le(int v) => [
  v & 0xFF,
  (v >>> 8) & 0xFF,
  (v >>> 16) & 0xFF,
  (v >>> 24) & 0xFF,
];

Uint8List _asBytes(List<int> data) =>
    data is Uint8List ? data : Uint8List.fromList(data);

void _checkLevel(int level) =>
    RangeError.checkValueInInterval(level, 0, 9, 'level');

int _encodeHint(Uint8List input) => input.length ~/ 2 + 64;

int _decodeHint(Uint8List input) => input.length * 4;
