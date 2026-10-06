/// The fixed tables of the DEFLATE format (RFC 1951, section 3.2.5), shared
/// by the encoder and the decoder.
library;

import 'dart:typed_data';

/// Shortest length each length code (257 + index) stands for.
const List<int> lengthBase = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, //
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
];

/// Extra bits that follow each length code.
const List<int> lengthExtra = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, //
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
];

/// Shortest distance each distance code stands for.
const List<int> distBase = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, //
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289,
  16385, 24577,
];

/// Extra bits that follow each distance code.
const List<int> distExtra = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, //
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
];

/// The order code-length code lengths are sent in a dynamic block header.
const List<int> codeLengthOrder = [
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, //
  11, 4, 12, 3, 13, 2, 14, 1, 15,
];

/// Literal/length code lengths of a fixed-Huffman block, all 288 symbols.
final Uint8List fixedLiteralLengths = Uint8List(288)
  ..fillRange(0, 144, 8)
  ..fillRange(144, 256, 9)
  ..fillRange(256, 280, 7)
  ..fillRange(280, 288, 8);

/// Distance code lengths of a fixed-Huffman block: 32 codes of five bits
/// (codes 30 and 31 are never valid in the data).
final Uint8List fixedDistanceLengths = Uint8List(32)..fillRange(0, 32, 5);

/// [code] of [length] bits, bit-reversed: DEFLATE packs Huffman codes
/// starting from their most significant bit, everything else from the least.
int reverseBits(int code, int length) {
  var r = 0;
  for (var i = 0; i < length; i++) {
    r = (r << 1) | (code & 1);
    code >>= 1;
  }
  return r;
}
