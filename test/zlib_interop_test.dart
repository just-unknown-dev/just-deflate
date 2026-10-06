// dart:io's codecs are real zlib: what this package writes must decode
// there, and what zlib writes must decode here.
@TestOn('vm')
library;

import 'dart:io' as io;

import 'package:just_deflate/just_deflate.dart';
import 'package:test/test.dart';

import 'data.dart';

void main() {
  for (final level in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]) {
    group('level $level', () {
      test('zlib reads ours', () {
        for (final sample in samples.entries) {
          expect(
            io.ZLibCodec().decode(ZlibCodec(level: level).encode(sample.value)),
            bytesEqual(sample.value),
            reason: 'zlib: ${sample.key}',
          );
          expect(
            io.GZipCodec().decode(GzipCodec(level: level).encode(sample.value)),
            bytesEqual(sample.value),
            reason: 'gzip: ${sample.key}',
          );
          expect(
            io.ZLibCodec(
              raw: true,
            ).decode(DeflateCodec(level: level).encode(sample.value)),
            bytesEqual(sample.value),
            reason: 'raw: ${sample.key}',
          );
        }
      });

      test('we read zlib', () {
        for (final sample in samples.entries) {
          expect(
            const ZlibCodec().decode(
              io.ZLibCodec(level: level).encode(sample.value),
            ),
            bytesEqual(sample.value),
            reason: 'zlib: ${sample.key}',
          );
          expect(
            const GzipCodec().decode(
              io.GZipCodec(level: level).encode(sample.value),
            ),
            bytesEqual(sample.value),
            reason: 'gzip: ${sample.key}',
          );
          expect(
            const DeflateCodec().decode(
              io.ZLibCodec(level: level, raw: true).encode(sample.value),
            ),
            bytesEqual(sample.value),
            reason: 'raw: ${sample.key}',
          );
        }
      });
    });
  }

  test('zlib\'s smaller windows and memory levels', () {
    final data = samples['mixed 400 KB']!;
    for (final windowBits in [9, 12, 15]) {
      for (final memLevel in [1, 8, 9]) {
        final packed = io.ZLibCodec(
          windowBits: windowBits,
          memLevel: memLevel,
        ).encode(data);
        expect(
          const ZlibCodec().decode(packed),
          bytesEqual(data),
          reason: 'windowBits $windowBits, memLevel $memLevel',
        );
      }
    }
  });

  test('zlib\'s other strategies', () {
    final data = samples['tile layer 300x200']!;
    for (final strategy in [
      io.ZLibOption.strategyFiltered,
      io.ZLibOption.strategyHuffmanOnly,
      io.ZLibOption.strategyRle,
      io.ZLibOption.strategyFixed,
    ]) {
      expect(
        const ZlibCodec().decode(io.ZLibCodec(strategy: strategy).encode(data)),
        bytesEqual(data),
        reason: 'strategy $strategy',
      );
    }
  });

  test('output is about as small as zlib\'s', () {
    for (final name in ['text 100 KB', 'tile layer 300x200', 'mixed 400 KB']) {
      final data = samples[name]!;
      for (final level in [1, 6, 9]) {
        final ours = ZlibCodec(level: level).encode(data).length;
        final theirs = io.ZLibCodec(level: level).encode(data).length;
        expect(
          ours,
          lessThanOrEqualTo(theirs * 1.05 + 16),
          reason: '$name at level $level: $ours vs zlib $theirs',
        );
      }
    }
  });
}
