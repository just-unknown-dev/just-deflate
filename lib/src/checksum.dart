/// The checksums of the zlib and gzip formats.
library;

import 'dart:typed_data';

/// The Adler-32 checksum (RFC 1950) of [data].
///
/// Pass the result of an earlier call as [adler] to continue a checksum over
/// data that arrives in pieces; the default starts a new one.
///
/// ```dart
/// adler32('Wikipedia'.codeUnits); // 0x11E60398
/// ```
int adler32(List<int> data, [int adler = 1]) {
  var a = adler & 0xFFFF;
  var b = (adler >>> 16) & 0xFFFF;
  final n = data.length;
  var i = 0;
  while (i < n) {
    // 5552 is the most bytes that can be summed before b passes 2^32, so
    // the modulo runs once per run rather than once per byte.
    final end = n - i > 5552 ? i + 5552 : n;
    for (; i < end; i++) {
      a += data[i] & 0xFF;
      b += a;
    }
    a %= 65521;
    b %= 65521;
  }
  return (b << 16) | a;
}

/// The CRC-32 checksum (ISO 3309, as gzip and PNG use it) of [data].
///
/// Pass the result of an earlier call as [crc] to continue a checksum over
/// data that arrives in pieces; the default starts a new one.
///
/// ```dart
/// crc32('123456789'.codeUnits); // 0xCBF43926
/// ```
int crc32(List<int> data, [int crc = 0]) {
  final table = _crcTable;
  var c = crc ^ 0xFFFFFFFF;
  for (var i = 0; i < data.length; i++) {
    c = table[(c ^ data[i]) & 0xFF] ^ (c >>> 8);
  }
  return c ^ 0xFFFFFFFF;
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c;
  }
  return table;
}();
