# Just Deflate

A pure Dart implementation of DEFLATE (RFC 1951) compression and decompression, with the zlib (RFC 1950) and gzip (RFC 1952) formats around it.

It has no dependencies and no `dart:io`, `dart:ffi` or native code, so it runs the same everywhere: Flutter on every platform, the web (dart2js) and Wasm (dart2wasm). It was written for the `just_tiled` package, where Tiled stores tile layers as zlib or gzip data, and for the Just Game Engine's level maps.

## Features

- **zlib, gzip and raw DEFLATE**, encoding and decoding.
- **Real compression**: LZ77 matching and dynamic Huffman codes, with zlib's settings for levels 0 to 9. Output is about the size of zlib's at the same level.
- **The same bytes on every platform.** Compressing the same data gives the same output on native, web and Wasm, so saved files don't change depending on where they were saved.
- **Reads anything zlib writes**: every block type, any window size, multi-member gzip files and gzip's optional header fields (name, comment, extra field, header CRC).
- **Checked decoding**: Adler-32 and CRC-32 checksums are verified, damaged data throws a `FormatException`, and `maxOutputSize` stops damaged or hostile data from unpacking without end.
- `adler32` and `crc32` checksum functions.

## Getting started

Add `just_deflate` to your `pubspec.yaml`:

```yaml
dependencies:
  just_deflate: ^0.1.0
```

## Usage

### zlib

```dart
import 'dart:typed_data';
import 'package:just_deflate/just_deflate.dart';

void main() {
  final data = Uint8List(64 * 64 * 4); // an empty 64 x 64 tile layer

  const zlib = ZlibCodec(); // level 6, zlib's default
  final packed = zlib.encode(data);
  print('${data.length} bytes -> ${packed.length} bytes');

  try {
    final unpacked = zlib.decode(packed, maxOutputSize: data.length);
    print('Decoded ${unpacked.length} bytes.');
  } on FormatException catch (e) {
    print('Invalid zlib data: $e');
  }
}
```

### gzip and raw DEFLATE

`GzipCodec` and `DeflateCodec` work the same way:

```dart
const gzip = GzipCodec(level: 9); // smallest output
final packed = gzip.encode(data);
final unpacked = gzip.decode(packed);

const raw = DeflateCodec(level: 1); // fastest
final stream = raw.encode(data); // no header, no checksum
```

### Levels

| Level | What it does |
| --- | --- |
| 0 | Stores the data uncompressed, in valid blocks. |
| 1-3 | Fast: takes the first good match it finds. |
| 4-9 | Lazy matching: checks whether the next position starts a longer match. Higher levels search further. |
| 6 | The default, zlib's balance of size and speed. |

A level outside 0-9 throws a `RangeError` from `encode`.

### Checksums

```dart
crc32('123456789'.codeUnits); // 0xCBF43926
adler32('Wikipedia'.codeUnits); // 0x11E60398

// Data in pieces: pass the running value back in.
var crc = crc32(firstPart);
crc = crc32(secondPart, crc);
```

## Notes

- zlib streams that need a preset dictionary (`FDICT`) are refused.
- Bytes after the end of a stream are ignored. In gzip data, anything after the last member that does not start another member is ignored.
- `encode` writes gzip headers with no file name, comment or time, and the operating system set to "unknown", so the output depends only on the data and the level.
- Everything is in memory: `encode` and `decode` take the whole input and return the whole output. There is no streaming API.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
