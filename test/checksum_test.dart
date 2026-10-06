import 'dart:typed_data';

import 'package:just_deflate/just_deflate.dart';
import 'package:test/test.dart';

import 'data.dart';

void main() {
  group('adler32', () {
    test('known values', () {
      expect(adler32(<int>[]), 1);
      expect(adler32('a'.codeUnits), 0x00620062);
      expect(adler32('abc'.codeUnits), 0x024D0127);
      expect(adler32('Wikipedia'.codeUnits), 0x11E60398);
    });

    test('long input keeps both sums in range', () {
      // 0xFF bytes push the sums fastest; zlib's adler32 gives this value.
      expect(
        adler32(Uint8List(100000)..fillRange(0, 100000, 0xFF)),
        0x149A302C,
      );
    });

    test('continues across pieces', () {
      final data = text(20000);
      final whole = adler32(data);
      var running = adler32(<int>[]);
      for (var i = 0; i < data.length; i += 777) {
        final end = i + 777 > data.length ? data.length : i + 777;
        running = adler32(Uint8List.sublistView(data, i, end), running);
      }
      expect(running, whole);
    });
  });

  group('crc32', () {
    test('known values', () {
      expect(crc32(<int>[]), 0);
      expect(crc32('123456789'.codeUnits), 0xCBF43926);
      expect(
        crc32('The quick brown fox jumps over the lazy dog'.codeUnits),
        0x414FA339,
      );
    });

    test('continues across pieces', () {
      final data = noise(5000);
      final whole = crc32(data);
      final half = crc32(Uint8List.sublistView(data, 0, 2500));
      expect(crc32(Uint8List.sublistView(data, 2500), half), whole);
    });

    test('results are unsigned on every platform', () {
      final c = crc32(noise(64, 3));
      expect(c, greaterThanOrEqualTo(0));
      expect(c, lessThanOrEqualTo(0xFFFFFFFF));
    });
  });
}
