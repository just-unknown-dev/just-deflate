/// The DEFLATE (RFC 1951) decoder.
library;

import 'dart:typed_data';

import 'tables.dart';

/// Decodes raw DEFLATE streams into one growing output buffer.
///
/// [inflate] may be called more than once (a gzip file can hold several
/// members); each call appends to the same output, and [maxOutputSize]
/// bounds the total.
class Inflater {
  /// An empty decoder. [sizeHint] is the expected output size, used for the
  /// first allocation only.
  Inflater({this.maxOutputSize, int sizeHint = 0})
    : _out = Uint8List(_initialCapacity(sizeHint, maxOutputSize));

  /// The most bytes the output may hold; more throws [FormatException].
  final int? maxOutputSize;

  Uint8List _out;
  int _outLen = 0;

  late Uint8List _in;
  int _pos = 0;
  int _start = 0;

  /// Where this stream's output starts; a back-reference may not reach
  /// past it into an earlier stream's.
  int _base = 0;

  /// Zero bytes fed in past the end of the input. A Huffman code is looked
  /// up by peeking ahead, which near the end of a stream can run past the
  /// last real byte; whether those bits were actually used is checked by
  /// [_checkInput].
  int _virtual = 0;
  int _bitBuf = 0;
  int _bitCount = 0;

  /// Bytes decoded so far.
  int get length => _outLen;

  /// The output from [start] up to [length], without copying.
  Uint8List view([int start = 0]) =>
      Uint8List.sublistView(_out, start, _outLen);

  /// Everything decoded, trimmed to [length].
  Uint8List takeBytes() =>
      _outLen == _out.length ? _out : _out.sublist(0, _outLen);

  /// Decodes the stream that starts at [input]`[start]`, appending to the
  /// output. Returns the offset of the first byte after the stream, where a
  /// zlib or gzip trailer begins.
  int inflate(Uint8List input, int start) {
    _in = input;
    _pos = _start = start;
    _base = _outLen;
    _virtual = _bitBuf = _bitCount = 0;
    var last = false;
    while (!last) {
      last = _bits(1) == 1;
      switch (_bits(2)) {
        case 0:
          _stored();
        case 1:
          _codes(_fixedLiterals, _fixedDistances);
        case 2:
          _dynamic();
        default:
          throw const FormatException('deflate: invalid block type');
      }
      _checkInput();
    }
    final used = (_pos - _start + _virtual) * 8 - _bitCount;
    return _start + (used + 7) ~/ 8;
  }

  // -- Bits -------------------------------------------------------------------

  /// Makes sure [n] (at most 16) bits are buffered.
  void _need(int n) {
    while (_bitCount < n) {
      int byte;
      if (_pos < _in.length) {
        byte = _in[_pos++];
      } else {
        // A valid stream never peeks more than two bytes past its end.
        if (++_virtual > 4) {
          throw const FormatException('deflate: unexpected end of data');
        }
        byte = 0;
      }
      _bitBuf |= byte << _bitCount;
      _bitCount += 8;
    }
  }

  int _bits(int n) {
    if (n == 0) return 0;
    _need(n);
    final v = _bitBuf & ((1 << n) - 1);
    _bitBuf >>>= n;
    _bitCount -= n;
    return v;
  }

  /// Throws if the bits read so far run past the end of the input.
  void _checkInput() {
    final used = (_pos - _start + _virtual) * 8 - _bitCount;
    if (used > (_in.length - _start) * 8) {
      throw const FormatException('deflate: unexpected end of data');
    }
  }

  int _symbol(_Table t) {
    _need(t.bits);
    final e = t.entries[_bitBuf & ((1 << t.bits) - 1)];
    final len = e & 15;
    if (len == 0) throw const FormatException('deflate: invalid Huffman code');
    _bitBuf >>>= len;
    _bitCount -= len;
    return e >> 4;
  }

  // -- Output -----------------------------------------------------------------

  void _reserve(int extra) {
    final need = _outLen + extra;
    final limit = maxOutputSize;
    if (limit != null && need > limit) {
      throw FormatException(
        'deflate: output is larger than maxOutputSize ($limit bytes)',
      );
    }
    if (need <= _out.length) return;
    var cap = _out.length * 2;
    if (cap < need) cap = need;
    if (limit != null && cap > limit) cap = limit;
    _out = Uint8List(cap)..setRange(0, _outLen, _out);
  }

  // -- Blocks -----------------------------------------------------------------

  void _stored() {
    // Skip to the next byte boundary; LEN and NLEN follow.
    _bits(_bitCount & 7);
    final len = _bits(16);
    final nlen = _bits(16);
    if (len != (~nlen & 0xFFFF)) {
      throw const FormatException('deflate: invalid stored block length');
    }
    _reserve(len);
    var left = len;
    // Whole bytes still in the bit buffer come first.
    while (left > 0 && _bitCount >= 8) {
      _out[_outLen++] = _bits(8);
      left--;
    }
    if (left == 0) return;
    if (_virtual > 0 || _pos + left > _in.length) {
      throw const FormatException('deflate: unexpected end of data');
    }
    _out.setRange(_outLen, _outLen + left, _in, _pos);
    _outLen += left;
    _pos += left;
  }

  void _dynamic() {
    final nlen = _bits(5) + 257;
    final ndist = _bits(5) + 1;
    final ncode = _bits(4) + 4;
    if (nlen > 286 || ndist > 30) {
      throw const FormatException(
        'deflate: too many length or distance symbols',
      );
    }
    final codeLens = Uint8List(19);
    for (var i = 0; i < ncode; i++) {
      codeLens[codeLengthOrder[i]] = _bits(3);
    }
    final codeTable = _Table.build(codeLens, codeLengths: true);

    final lens = Uint8List(nlen + ndist);
    var i = 0;
    while (i < lens.length) {
      final sym = _symbol(codeTable);
      if (sym < 16) {
        lens[i++] = sym;
        continue;
      }
      int value, repeat;
      if (sym == 16) {
        if (i == 0) {
          throw const FormatException(
            'deflate: repeated code length with no first length',
          );
        }
        value = lens[i - 1];
        repeat = 3 + _bits(2);
      } else if (sym == 17) {
        value = 0;
        repeat = 3 + _bits(3);
      } else {
        value = 0;
        repeat = 11 + _bits(7);
      }
      if (i + repeat > lens.length) {
        throw const FormatException('deflate: invalid code length repeat');
      }
      lens.fillRange(i, i + repeat, value);
      i += repeat;
    }
    if (lens[256] == 0) {
      throw const FormatException('deflate: missing end-of-block code');
    }
    _codes(
      _Table.build(Uint8List.sublistView(lens, 0, nlen)),
      _Table.build(Uint8List.sublistView(lens, nlen)),
    );
  }

  void _codes(_Table literals, _Table distances) {
    while (true) {
      var sym = _symbol(literals);
      if (sym < 256) {
        if (_outLen == _out.length) _reserve(1);
        _out[_outLen++] = sym;
        continue;
      }
      if (sym == 256) return;
      sym -= 257;
      if (sym >= 29) {
        throw const FormatException('deflate: invalid literal/length code');
      }
      final len = lengthBase[sym] + _bits(lengthExtra[sym]);
      final dsym = _symbol(distances);
      if (dsym >= 30) {
        throw const FormatException('deflate: invalid distance code');
      }
      final dist = distBase[dsym] + _bits(distExtra[dsym]);
      if (dist > _outLen - _base) {
        throw const FormatException('deflate: distance too far back');
      }
      _reserve(len);
      final from = _outLen - dist;
      if (dist >= len) {
        _out.setRange(_outLen, _outLen + len, _out, from);
        _outLen += len;
      } else {
        // The copy overlaps what it writes: a run, byte by byte.
        for (var k = 0; k < len; k++) {
          _out[_outLen] = _out[from + k];
          _outLen++;
        }
      }
    }
  }
}

int _initialCapacity(int hint, int? limit) {
  var cap = hint > 0 ? hint : 1024;
  if (limit != null && cap > limit) cap = limit;
  return cap;
}

final _Table _fixedLiterals = _Table.build(fixedLiteralLengths);
final _Table _fixedDistances = _Table.build(fixedDistanceLengths);

/// A canonical Huffman code as one lookup table indexed by the next [bits]
/// input bits. Each entry is `symbol << 4 | codeLength`; 0 marks bits that
/// start no code.
class _Table {
  _Table(this.entries, this.bits);

  final Uint16List entries;
  final int bits;

  /// The table for the code with these per-symbol [lengths] (0 = unused).
  ///
  /// Like zlib, accepts an incomplete code only when it is a single code of
  /// one bit, and never for the code-length code.
  static _Table build(Uint8List lengths, {bool codeLengths = false}) {
    final counts = List<int>.filled(16, 0);
    var maxLen = 0;
    for (final len in lengths) {
      counts[len]++;
      if (len > maxLen) maxLen = len;
    }
    if (maxLen == 0) return _Table(Uint16List(2), 1);
    counts[0] = 0;
    var left = 1;
    for (var len = 1; len <= 15; len++) {
      left = (left << 1) - counts[len];
      if (left < 0) {
        throw const FormatException('deflate: over-subscribed Huffman code');
      }
    }
    if (left > 0 && (codeLengths || maxLen != 1)) {
      throw const FormatException('deflate: incomplete Huffman code');
    }

    final next = List<int>.filled(16, 0);
    var code = 0;
    for (var len = 1; len <= 15; len++) {
      code = (code + counts[len - 1]) << 1;
      next[len] = code;
    }
    final size = 1 << maxLen;
    final entries = Uint16List(size);
    for (var sym = 0; sym < lengths.length; sym++) {
      final len = lengths[sym];
      if (len == 0) continue;
      final entry = (sym << 4) | len;
      for (var i = reverseBits(next[len]++, len); i < size; i += 1 << len) {
        entries[i] = entry;
      }
    }
    return _Table(entries, maxLen);
  }
}
