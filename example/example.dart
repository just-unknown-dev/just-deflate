import 'dart:typed_data';

import 'package:just_deflate/just_deflate.dart';

void main() {
  // The codecs are stateless and can be reused.
  const zlib = ZlibCodec();
  const gzip = GzipCodec(level: 9);

  // A tile layer: 64 x 64 little-endian ids, mostly empty.
  final layer = ByteData(64 * 64 * 4);
  for (var i = 0; i < 64 * 64; i += 7) {
    layer.setUint32(i * 4, 1 + i % 3, Endian.little);
  }
  final original = layer.buffer.asUint8List();
  print('Original:   ${original.length} bytes');

  // --- Encoding ---
  final packed = zlib.encode(original);
  print('zlib:       ${packed.length} bytes');
  print('gzip (9):   ${gzip.encode(original).length} bytes');

  // --- Decoding ---
  try {
    // A limit keeps damaged or hostile data from unpacking without end.
    final unpacked = zlib.decode(packed, maxOutputSize: original.length);
    print('Round-trip OK: ${_same(original, unpacked)}');
  } on FormatException catch (e) {
    print('Error decoding data: $e');
  }

  print(
    'CRC-32 of "123456789": 0x${crc32('123456789'.codeUnits).toRadixString(16)}',
  );
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
