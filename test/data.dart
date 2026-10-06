import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';

/// [n] bytes of a repeating sentence.
Uint8List text(int n) => Uint8List.fromList(
  List.generate(
    n,
    (i) => 'Tiled maps: zlib, gzip and zstd. '.codeUnitAt(i % 33),
  ),
);

/// A [w] x [h] tile layer as Tiled stores it: little-endian ids, a ground
/// row, a few posts above it and scattered decorations.
Uint8List layer(int w, int h) {
  final b = ByteData(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final x = i % w, y = i ~/ w;
    final id = y == h - 1
        ? 1
        : (y > h - 4 && x % 5 == 0
              ? 2
              : ((x * 7 + y * 13) % 23 == 0 ? 3 + x % 4 : 0));
    b.setUint32(i * 4, id, Endian.little);
  }
  return b.buffer.asUint8List();
}

/// [n] bytes from a seeded generator: data that does not compress.
Uint8List noise(int n, [int seed = 7]) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

/// Inputs that between them reach every block type and code path.
final Map<String, Uint8List> samples = {
  'empty': Uint8List(0),
  'one byte': Uint8List.fromList([42]),
  'two bytes': Uint8List.fromList([0, 255]),
  'every byte value': Uint8List.fromList(List.generate(256, (i) => i)),
  'short text': text(40),
  'text 100 KB': text(100000),
  'zeros 300 KB': Uint8List(300000),
  'noise 70 KB': noise(70000),
  'tile layer 64x64': layer(64, 64),
  'tile layer 300x200': layer(300, 200),
  // Runs longer than the longest match, and matches near the 32 KiB limit.
  'runs': Uint8List.fromList([
    for (var r = 0; r < 40; r++) ...List.filled(259 + r * 13, r & 3),
  ]),
  'far repeat': Uint8List.fromList([...noise(32760, 1), ...noise(600, 1)]),
  'mixed 400 KB': Uint8List.fromList([
    for (var k = 0; k < 8; k++) ...[...noise(20000, k), ...text(30000)],
  ]),
};

Matcher bytesEqual(List<int> expected) => _BytesEqual(expected);

/// Like `equals`, but reports the first difference instead of dumping
/// both lists.
class _BytesEqual extends Matcher {
  _BytesEqual(this.expected);

  final List<int> expected;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> state) {
    if (item is! List<int> || item.length != expected.length) return false;
    for (var i = 0; i < item.length; i++) {
      if (item[i] != expected[i]) return false;
    }
    return true;
  }

  @override
  Description describe(Description d) =>
      d.add('${expected.length} bytes equal to the original');

  @override
  Description describeMismatch(
    Object? item,
    Description d,
    Map<dynamic, dynamic> state,
    bool verbose,
  ) {
    if (item is! List<int>) return d.add('is not a list of bytes');
    if (item.length != expected.length) {
      return d.add('has ${item.length} bytes');
    }
    for (var i = 0; i < item.length; i++) {
      if (item[i] != expected[i]) {
        return d.add('differs first at byte $i: ${item[i]} != ${expected[i]}');
      }
    }
    return d;
  }
}
