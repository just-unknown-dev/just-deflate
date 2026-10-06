/// Pure Dart DEFLATE (RFC 1951) compression and decompression, with the
/// zlib (RFC 1950) and gzip (RFC 1952) formats around it.
///
/// ```dart
/// import 'package:just_deflate/just_deflate.dart';
///
/// const zlib = ZlibCodec();
/// final packed = zlib.encode(bytes);
/// final unpacked = zlib.decode(packed);
/// ```
///
/// [DeflateCodec], [ZlibCodec] and [GzipCodec] all compress at a level from
/// 0 to 9 and decode with an optional `maxOutputSize`. [adler32] and
/// [crc32] are the checksums the formats use.
library;

export 'src/checksum.dart' show adler32, crc32;
export 'src/codecs.dart' show DeflateCodec, GzipCodec, ZlibCodec;
