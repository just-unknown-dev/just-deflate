import 'dart:math';
import 'dart:typed_data';

import 'package:just_deflate/just_deflate.dart';
import 'package:test/test.dart';

import 'data.dart';

/// Bytes from a string of bits in stream order: the first bit is the least
/// significant bit of the first byte. Spaces are for reading only.
Uint8List _bits(String bits) {
  final clean = bits.replaceAll(' ', '');
  final out = Uint8List((clean.length + 7) ~/ 8);
  for (var i = 0; i < clean.length; i++) {
    if (clean[i] == '1') out[i >> 3] |= 1 << (i & 7);
  }
  return out;
}

Matcher _fails(String message) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(message)),
);

void main() {
  group('levels', () {
    test('outside 0-9 are refused', () {
      for (final level in [-1, 10]) {
        expect(() => DeflateCodec(level: level).encode([1]), throwsRangeError);
        expect(() => ZlibCodec(level: level).encode([1]), throwsRangeError);
        expect(() => GzipCodec(level: level).encode([1]), throwsRangeError);
      }
    });
  });

  group('deflate', () {
    const raw = DeflateCodec();

    test('a stored block by hand', () {
      expect(raw.decode([0x01, 3, 0, 0xFC, 0xFF, 97, 98, 99]), [97, 98, 99]);
    });

    test('stored block with a wrong NLEN', () {
      expect(() => raw.decode([0x01, 1, 0, 0, 0, 7]), _fails('stored block'));
    });

    test('stored block cut short', () {
      expect(
        () => raw.decode([0x01, 5, 0, 0xFA, 0xFF, 97, 98]),
        _fails('unexpected end'),
      );
    });

    test('block type 3', () {
      expect(() => raw.decode(_bits('1 11')), _fails('invalid block type'));
    });

    test('a match before any output', () {
      // Fixed block: length code 257 (0000001), distance code 0 (00000).
      expect(
        () => raw.decode(_bits('1 10 0000001 00000')),
        _fails('too far back'),
      );
    });

    test('literal/length code 286', () {
      expect(
        () => raw.decode(_bits('1 10 11000110')),
        _fails('invalid literal/length code'),
      );
    });

    test('distance code 30', () {
      expect(
        () => raw.decode(_bits('1 10 0000001 11110')),
        _fails('invalid distance code'),
      );
    });

    test('too many length codes', () {
      expect(
        () => raw.decode(_bits('1 01 11111 00000 0000')),
        _fails('too many length or distance symbols'),
      );
    });

    test('over-subscribed code-length code', () {
      expect(
        () => raw.decode(_bits('1 01 00000 00000 0000 100 100 100 100')),
        _fails('over-subscribed'),
      );
    });

    test('incomplete code-length code', () {
      expect(
        () => raw.decode(_bits('1 01 00000 00000 0000 100 000 000 000')),
        _fails('incomplete'),
      );
    });

    test('a repeat before any length', () {
      // Code-length code: 16 and 0, one bit each; the first symbol is 16.
      expect(
        () => raw.decode(_bits('1 01 00000 00000 0000 100 000 000 100 1 00')),
        _fails('no first length'),
      );
    });

    test('empty input', () {
      expect(() => raw.decode([]), _fails('unexpected end'));
    });
  });

  group('zlib', () {
    const zlib = ZlibCodec();
    final good = zlib.encode(text(2000));

    test('header problems', () {
      expect(() => zlib.decode([0x78]), _fails('truncated header'));
      expect(() => zlib.decode([0x77, 0x9C, 3, 0]), _fails('method'));
      expect(() => zlib.decode([0x88, 0x98, 3, 0]), _fails('window size'));
      expect(() => zlib.decode([0x78, 0x9D, 3, 0]), _fails('header check'));
      expect(
        () => zlib.decode([0x78, 0xBB, 0, 0, 0, 1, 3, 0]),
        _fails('preset dictionaries'),
      );
    });

    test('a wrong checksum', () {
      final bad = Uint8List.fromList(good)..[good.length - 1] ^= 1;
      expect(() => zlib.decode(bad), _fails('incorrect data check'));
    });

    test('a missing checksum', () {
      expect(
        () => zlib.decode(good.sublist(0, good.length - 2)),
        _fails('truncated checksum'),
      );
    });

    test('maxOutputSize one byte short', () {
      expect(
        () => zlib.decode(good, maxOutputSize: 1999),
        _fails('maxOutputSize'),
      );
    });
  });

  group('gzip', () {
    const gzip = GzipCodec();
    final good = gzip.encode(text(2000));

    test('header problems', () {
      expect(() => gzip.decode([0x1F, 0x8B, 8]), _fails('truncated header'));
      expect(
        () => gzip.decode([0x1F, 0x8C, 8, 0, 0, 0, 0, 0, 0, 0, 3, 0]),
        _fails('not gzip'),
      );
      expect(
        () => gzip.decode([0x1F, 0x8B, 7, 0, 0, 0, 0, 0, 0, 0, 3, 0]),
        _fails('method'),
      );
      expect(
        () => gzip.decode([0x1F, 0x8B, 8, 0x20, 0, 0, 0, 0, 0, 0, 3, 0]),
        _fails('reserved'),
      );
      // FNAME with no terminating zero.
      expect(
        () => gzip.decode([0x1F, 0x8B, 8, 0x08, 0, 0, 0, 0, 0, 0, 97, 98]),
        _fails('truncated header'),
      );
    });

    test('a wrong CRC-32', () {
      final bad = Uint8List.fromList(good)..[good.length - 8] ^= 1;
      expect(() => gzip.decode(bad), _fails('incorrect data check'));
    });

    test('a wrong size', () {
      final bad = Uint8List.fromList(good)..[good.length - 4] ^= 1;
      expect(() => gzip.decode(bad), _fails('incorrect length check'));
    });

    test('a missing trailer', () {
      expect(
        () => gzip.decode(good.sublist(0, good.length - 3)),
        _fails('truncated trailer'),
      );
    });
  });

  group('damaged data never escapes as another error', () {
    final inputs = {
      'deflate': (const DeflateCodec().encode, const DeflateCodec().decode),
      'zlib': (const ZlibCodec().encode, const ZlibCodec().decode),
      'gzip': (const GzipCodec().encode, const GzipCodec().decode),
    };
    final original = Uint8List.fromList([
      ...layer(20, 12),
      ...text(600),
      ...noise(300),
    ]);

    for (final entry in inputs.entries) {
      final (encode, decode) = entry.value;

      test('${entry.key}: every truncation', () {
        final packed = encode(original);
        for (var n = 0; n < packed.length; n++) {
          expect(
            () => decode(Uint8List.sublistView(packed, 0, n)),
            throwsA(isA<FormatException>()),
            reason: 'first $n of ${packed.length} bytes',
          );
        }
      });

      test('${entry.key}: random damage', () {
        final packed = encode(original);
        final random = Random(entry.key.length);
        for (var round = 0; round < 400; round++) {
          final bad = Uint8List.fromList(packed);
          for (var k = 0; k < 1 + round % 3; k++) {
            bad[random.nextInt(bad.length)] ^= 1 << random.nextInt(8);
          }
          try {
            final out = decode(bad, maxOutputSize: 1 << 20);
            // Only raw deflate, with no checksum, can come out with
            // different bytes.
            if (entry.key != 'deflate') expect(out, bytesEqual(original));
          } on FormatException {
            // Expected.
          }
        }
      });

      test('${entry.key}: noise', () {
        for (var seed = 0; seed < 200; seed++) {
          try {
            decode(noise(1 + seed * 3, seed), maxOutputSize: 1 << 20);
          } on FormatException {
            // Expected.
          }
        }
      });
    }
  });
}
