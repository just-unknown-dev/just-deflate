import 'dart:convert';
import 'dart:typed_data';

import 'package:just_deflate/just_deflate.dart';
import 'package:test/test.dart';

import 'data.dart';

typedef _Codec = ({
  Uint8List Function(List<int>, int level) encode,
  Uint8List Function(List<int>, {int? maxOutputSize}) decode,
});

final Map<String, _Codec> _codecs = {
  'deflate': (
    encode: (d, l) => DeflateCodec(level: l).encode(d),
    decode: const DeflateCodec().decode,
  ),
  'zlib': (
    encode: (d, l) => ZlibCodec(level: l).encode(d),
    decode: const ZlibCodec().decode,
  ),
  'gzip': (
    encode: (d, l) => GzipCodec(level: l).encode(d),
    decode: const GzipCodec().decode,
  ),
};

void main() {
  group('round trip', () {
    for (final codec in _codecs.entries) {
      for (final level in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]) {
        test('${codec.key} at level $level', () {
          for (final sample in samples.entries) {
            final packed = codec.value.encode(sample.value, level);
            expect(
              codec.value.decode(packed),
              bytesEqual(sample.value),
              reason: sample.key,
            );
          }
        });
      }
    }
  });

  group('compression', () {
    test('level 0 stores the data as it is', () {
      final data = noise(70000);
      final packed = const ZlibCodec(level: 0).encode(data);
      // Two stored blocks: 5 bytes each, plus the 2-byte header and the
      // 4-byte checksum.
      expect(packed.length, data.length + 2 * 5 + 6);
    });

    test('tile layers shrink a lot', () {
      final data = layer(64, 64);
      for (final level in [1, 6, 9]) {
        final packed = ZlibCodec(level: level).encode(data);
        expect(packed.length, lessThan(data.length ~/ 20), reason: '$level');
      }
    });

    test('data that will not compress grows only by block overhead', () {
      final data = noise(100000);
      final packed = const ZlibCodec().encode(data);
      expect(packed.length, lessThan(data.length + 100));
    });

    test('a long run is a handful of bytes', () {
      expect(
        const DeflateCodec().encode(Uint8List(100000)).length,
        lessThan(200),
      );
    });
  });

  group('the same bytes on every platform', () {
    // CRCs of this package's output on the Dart VM; the web and Wasm must
    // match them, or saved files would differ between platforms.
    const layerCrc = {
      0: 0x72f127a0,
      1: 0x57b05878,
      4: 0xf6343af9,
      6: 0xad8d456c,
      9: 0x051066c9,
    };
    const textCrc = {
      0: 0x31799eea,
      1: 0xd79c9dee,
      4: 0xc4aa134d,
      6: 0xc4aa134d,
      9: 0xfc015cd9,
    };
    for (final level in layerCrc.keys) {
      test('level $level', () {
        expect(
          crc32(ZlibCodec(level: level).encode(layer(64, 64))),
          layerCrc[level],
        );
        expect(
          crc32(GzipCodec(level: level).encode(text(100000))),
          textCrc[level],
        );
      });
    }

    test('encoding twice gives the same bytes', () {
      final data = samples['mixed 400 KB']!;
      expect(
        const GzipCodec().encode(data),
        bytesEqual(const GzipCodec().encode(data)),
      );
    });
  });

  group('real zlib output', () {
    // Made by zlib itself (dart:io), so these also run where dart:io
    // does not.
    test('zlib, level 9', () {
      final packed = base64Decode(
        'eNoLycxJTVHITSwotlKoyslM0lFIr8osUEjMS1GoKi5J0VMIgSgAAB+jDdo=',
      );
      expect(const ZlibCodec().decode(packed), bytesEqual(text(40)));
    });

    test('gzip, level 6', () {
      final packed = base64Decode(
        'H4sIAAAAAAAACgvJzElNUchNLCi2UqjKyUzSUUivyixQSMxLUagqLknRUwgZVTCqYFTB'
        'UFcAAPjsC1XoAwAA',
      );
      expect(const GzipCodec().decode(packed), bytesEqual(text(1000)));
    });

    test('raw deflate of a tile layer', () {
      final packed = base64Decode(
        'Y2agHWAjQg0zDe0nBhBjPwsd3DHU7WelgzuGuv3E5AdagqFgP7XLAyYSxZiJVEeu+aSK'
        'MdIYAwA=',
      );
      expect(const DeflateCodec().decode(packed), bytesEqual(layer(24, 16)));
    });

    test('zlib, level 1, a larger layer', () {
      final packed = base64Decode(
        'eAHt1uFqAyEYRFHTpH3/Ry77Q7hkigR2Z2HsFEonNuh61G99Dt/Pj6/r8W3sm10/+eHi'
        'XJ816F0+r/VjnPpv6v7hpOtDDc07+DjraaoPV7o+1NCc6sOZ3PW+4ZhXZOf54vPVhxqa'
        'U304k9T7irP+1IcC65y6fzgrZz2tD6U110dN2OL04TjOepp6vupDgXVO3T+cVep9znm+'
        'dvNx1tPU/cM1rg81NO/g46wXqT5c6fpQQ/MOPqn3Fef54krXhxqaU304k9T7irP+1IcC'
        '65y6fzgrZz2tD6U110dN2OL04TjOepp6vupDgXVO3T+cVep9znm+6kOBdU7dP5yV831T'
        'H0prvsvHWS9S9w9Xoz7U0LyDT+p9xXm+uNL1oYbmHXzuet+o3rkWZ/3hk9WHGppTfTgT'
        'Zz2tD6U110dN2OL04TjOepp6vupDgXVO2z9ff0zH2TZ9HGO8n69PxvjkOwcRvzfvu2yb'
        'jGfbps9V/c1+jr+Hz/vzPcYY//n3F8ezA4s=',
      );
      expect(const ZlibCodec().decode(packed), bytesEqual(layer(64, 64)));
    });
  });

  group('gzip members', () {
    test('several members decode as one', () {
      final a = text(5000), b = noise(3000), c = Uint8List(0);
      final packed = [
        ...const GzipCodec().encode(a),
        ...const GzipCodec(level: 0).encode(b),
        ...const GzipCodec(level: 9).encode(c),
      ];
      expect(const GzipCodec().decode(packed), bytesEqual([...a, ...b, ...c]));
    });

    test('optional header fields are skipped and checked', () {
      final data = text(300);
      // FTEXT | FHCRC | FEXTRA | FNAME | FCOMMENT.
      final header = <int>[
        0x1F, 0x8B, 8, 0x1F, 1, 2, 3, 4, 0, 3, //
        4, 0, 0xAA, 0xBB, 0xCC, 0xDD, // FEXTRA: four bytes
        ...'map.tmx'.codeUnits, 0, // FNAME
        ...'a comment'.codeUnits, 0, // FCOMMENT
      ];
      final hcrc = crc32(header) & 0xFFFF;
      final crc = crc32(data);
      final packed = [
        ...header,
        hcrc & 0xFF,
        hcrc >> 8,
        ...const DeflateCodec().encode(data),
        for (final v in [crc, data.length]) ...[
          v & 0xFF,
          (v >>> 8) & 0xFF,
          (v >>> 16) & 0xFF,
          (v >>> 24) & 0xFF,
        ],
      ];
      expect(const GzipCodec().decode(packed), bytesEqual(data));

      final badHeader = [...packed]..[packed.indexOf(0x6D)] ^= 1; // 'm'
      expect(
        () => const GzipCodec().decode(badHeader),
        throwsA(isA<FormatException>()),
      );
    });

    test('the header names no file, time or system', () {
      final packed = const GzipCodec().encode(text(10));
      expect(packed.sublist(0, 10), [0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 255]);
      expect(const GzipCodec(level: 9).encode(text(10))[8], 2);
      expect(const GzipCodec(level: 1).encode(text(10))[8], 4);
    });
  });

  group('framing', () {
    test('zlib headers carry the level', () {
      String head(int level) => ZlibCodec(level: level)
          .encode(text(10))
          .sublist(0, 2)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(head(0), '7801');
      expect(head(1), '7801');
      expect(head(3), '785e');
      expect(head(6), '789c');
      expect(head(9), '78da');
    });

    test('bytes after the stream are ignored', () {
      final data = text(1000);
      final tail = [1, 2, 3, 4, 5];
      expect(
        const ZlibCodec().decode([...const ZlibCodec().encode(data), ...tail]),
        bytesEqual(data),
      );
      expect(
        const DeflateCodec().decode([
          ...const DeflateCodec().encode(data),
          ...tail,
        ]),
        bytesEqual(data),
      );
      expect(
        const GzipCodec().decode([...const GzipCodec().encode(data), ...tail]),
        bytesEqual(data),
      );
    });

    test('a plain List<int> works as well as a Uint8List', () {
      final data = List<int>.generate(5000, (i) => (i * 31) & 0xFF);
      final packed = const ZlibCodec().encode(data);
      expect(const ZlibCodec().decode(packed.toList()), bytesEqual(data));
    });

    test('maxOutputSize allows exactly the data', () {
      final data = layer(32, 32);
      final packed = const ZlibCodec().encode(data);
      expect(
        const ZlibCodec().decode(packed, maxOutputSize: data.length),
        bytesEqual(data),
      );
      expect(
        const ZlibCodec().decode(
          const ZlibCodec().encode(Uint8List(0)),
          maxOutputSize: 0,
        ),
        isEmpty,
      );
    });
  });
}
