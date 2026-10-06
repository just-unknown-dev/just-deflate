/// Building Huffman codes for the encoder.
library;

import 'dart:typed_data';

import 'tables.dart';

/// Code lengths of an optimal prefix code for [freq], none longer than
/// [maxLength] bits. Symbols with no uses get length 0.
///
/// Like zlib, always gives at least two symbols a code, so the code is
/// complete — some decoders reject a one-symbol code.
Uint8List huffmanLengths(List<int> freq, int maxLength) {
  final n = freq.length;
  final lengths = Uint8List(n);
  final syms = <int>[
    for (var i = 0; i < n; i++)
      if (freq[i] > 0) i,
  ];
  for (var i = 0; syms.length < 2 && i < n; i++) {
    if (freq[i] == 0) syms.add(i);
  }
  // Least used first; ties by symbol so the output never depends on the
  // sort algorithm.
  syms.sort((a, b) {
    final d = freq[a] - freq[b];
    return d != 0 ? d : a - b;
  });

  // Huffman's algorithm with two queues: the sorted leaves, and the
  // internal nodes, which come out already in weight order.
  final m = syms.length;
  final weight = List<int>.filled(2 * m - 1, 0);
  final parent = Int32List(2 * m - 1);
  for (var i = 0; i < m; i++) {
    weight[i] = freq[syms[i]];
  }
  var leaf = 0, inner = m, made = m;
  int pick() {
    if (leaf < m && (inner >= made || weight[leaf] <= weight[inner])) {
      return leaf++;
    }
    return inner++;
  }

  for (; made < 2 * m - 1; made++) {
    final a = pick(), b = pick();
    weight[made] = weight[a] + weight[b];
    parent[a] = made;
    parent[b] = made;
  }

  // Depths: a parent always has a higher index than its children.
  final depth = Int32List(2 * m - 1);
  for (var k = 2 * m - 3; k >= 0; k--) {
    depth[k] = depth[parent[k]] + 1;
  }
  final counts = Int32List(m + 1);
  for (var i = 0; i < m; i++) {
    counts[depth[i]]++;
  }

  // Too-long codes are cut to maxLength, then shorter codes are lengthened
  // one at a time until the code is complete again.
  if (counts.length > maxLength + 1) {
    for (var d = maxLength + 1; d < counts.length; d++) {
      counts[maxLength] += counts[d];
      counts[d] = 0;
    }
    var total = 0;
    for (var d = 1; d <= maxLength; d++) {
      total += counts[d] << (maxLength - d);
    }
    while (total != 1 << maxLength) {
      counts[maxLength]--;
      for (var d = maxLength - 1; d > 0; d--) {
        if (counts[d] > 0) {
          counts[d]--;
          counts[d + 1] += 2;
          break;
        }
      }
      total--;
    }
  }

  // The longest codes go to the least used symbols.
  var s = 0;
  for (var d = counts.length - 1; d > 0; d--) {
    for (var c = 0; c < counts[d]; c++) {
      lengths[syms[s++]] = d;
    }
  }
  return lengths;
}

/// The canonical codes for [lengths], bit-reversed ready to write.
Uint16List canonicalCodes(Uint8List lengths) {
  final counts = List<int>.filled(16, 0);
  for (final len in lengths) {
    counts[len]++;
  }
  counts[0] = 0;
  final next = List<int>.filled(16, 0);
  var code = 0;
  for (var len = 1; len <= 15; len++) {
    code = (code + counts[len - 1]) << 1;
    next[len] = code;
  }
  final codes = Uint16List(lengths.length);
  for (var sym = 0; sym < lengths.length; sym++) {
    final len = lengths[sym];
    if (len != 0) codes[sym] = reverseBits(next[len]++, len);
  }
  return codes;
}
