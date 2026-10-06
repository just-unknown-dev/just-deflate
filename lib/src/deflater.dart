/// The DEFLATE (RFC 1951) encoder.
library;

import 'dart:typed_data';

import 'huffman.dart';
import 'tables.dart';

/// Writes bytes and one raw DEFLATE stream into a growing buffer.
///
/// The match finder and the per-level settings follow zlib's, so output
/// sizes are close to zlib's at the same level; the bytes themselves differ.
/// Output is the same on every platform.
class Deflater {
  /// An empty buffer. [sizeHint] sizes the first allocation.
  Deflater({int sizeHint = 0})
    : _out = Uint8List(sizeHint > 64 ? sizeHint : 64);

  Uint8List _out;
  int _outLen = 0;
  int _bitBuf = 0;
  int _bitCount = 0;

  /// Appends [bytes] as they are — a header or trailer around the stream.
  void addBytes(List<int> bytes) {
    for (final b in bytes) {
      _byte(b);
    }
  }

  /// Everything written, trimmed.
  Uint8List takeBytes() => _out.sublist(0, _outLen);

  /// Compresses [input] at [level] (0 = stored, 9 = smallest) as one
  /// complete stream, ending on a byte boundary.
  void deflate(Uint8List input, int level) {
    if (level == 0) {
      _storedBlocks(input, 0, input.length, true);
    } else {
      _Matcher(this, input, _levels[level]).run();
    }
    _alignToByte();
  }

  // -- Bits -------------------------------------------------------------------

  void _byte(int b) {
    if (_outLen == _out.length) {
      _out = Uint8List(_out.length * 2)..setRange(0, _outLen, _out);
    }
    _out[_outLen++] = b;
  }

  /// Writes the low [n] (at most 16) bits of [value], least significant
  /// first.
  void _bits(int value, int n) {
    _bitBuf |= value << _bitCount;
    _bitCount += n;
    while (_bitCount >= 8) {
      _byte(_bitBuf & 0xFF);
      _bitBuf >>>= 8;
      _bitCount -= 8;
    }
  }

  void _alignToByte() {
    if (_bitCount > 0) _bits(0, 8 - _bitCount);
  }

  // -- Blocks -----------------------------------------------------------------

  /// [input]`[start, end)` as stored blocks of at most 65535 bytes.
  void _storedBlocks(Uint8List input, int start, int end, bool last) {
    var pos = start;
    do {
      final len = end - pos > 65535 ? 65535 : end - pos;
      final isLast = last && pos + len == end;
      _bits(isLast ? 1 : 0, 1);
      _bits(0, 2);
      _alignToByte();
      _bits(len, 16);
      _bits(~len & 0xFFFF, 16);
      for (var i = pos; i < pos + len; i++) {
        _byte(input[i]);
      }
      pos += len;
    } while (pos < end);
  }

  /// One block of the [count] symbols in [lit] / [dist], covering
  /// [input]`[start, end)`: stored, fixed or dynamic Huffman, whichever is
  /// smallest.
  void _block(
    Uint8List input,
    int start,
    int end,
    Uint16List lit,
    Uint16List dist,
    int count,
    Int32List litFreq,
    Int32List distFreq,
    bool last,
  ) {
    litFreq[256]++;

    var extraBits = 0;
    for (var i = 0; i < 29; i++) {
      extraBits += litFreq[257 + i] * lengthExtra[i];
    }
    for (var i = 0; i < 30; i++) {
      extraBits += distFreq[i] * distExtra[i];
    }

    // Fixed Huffman.
    var fixedBits = 3 + extraBits;
    for (var i = 0; i < 286; i++) {
      fixedBits += litFreq[i] * fixedLiteralLengths[i];
    }
    for (var i = 0; i < 30; i++) {
      fixedBits += distFreq[i] * 5;
    }

    // Dynamic Huffman.
    final litLens = huffmanLengths(litFreq, 15);
    final distLens = huffmanLengths(distFreq, 15);
    var nlit = 286;
    while (nlit > 257 && litLens[nlit - 1] == 0) {
      nlit--;
    }
    var ndist = 30;
    while (ndist > 1 && distLens[ndist - 1] == 0) {
      ndist--;
    }
    final header = _CodeLengthRuns()
      ..add(litLens, nlit)
      ..add(distLens, ndist);
    final clLens = huffmanLengths(header.freq, 7);
    var ncode = 19;
    while (ncode > 4 && clLens[codeLengthOrder[ncode - 1]] == 0) {
      ncode--;
    }
    var dynamicBits = 3 + 14 + 3 * ncode + extraBits;
    for (var i = 0; i < 19; i++) {
      dynamicBits += header.freq[i] * clLens[i];
    }
    dynamicBits += header.freq[16] * 2 + header.freq[17] * 3;
    dynamicBits += header.freq[18] * 7;
    for (var i = 0; i < nlit; i++) {
      dynamicBits += litFreq[i] * litLens[i];
    }
    for (var i = 0; i < ndist; i++) {
      dynamicBits += distFreq[i] * distLens[i];
    }

    // Stored, at worst: each block's header and padding plus LEN / NLEN.
    final raw = end - start;
    final storedBlocks = raw == 0 ? 1 : (raw + 65534) ~/ 65535;
    final storedBits = storedBlocks * (3 + 7 + 32) + raw * 8;

    if (storedBits <= fixedBits && storedBits <= dynamicBits) {
      _storedBlocks(input, start, end, last);
      return;
    }
    _bits(last ? 1 : 0, 1);
    if (fixedBits <= dynamicBits) {
      _bits(1, 2);
      _symbols(
        lit,
        dist,
        count,
        _fixedLiteral,
        fixedLiteralLengths,
        _fixedDistance,
        fixedDistanceLengths,
      );
      return;
    }
    _bits(2, 2);
    _bits(nlit - 257, 5);
    _bits(ndist - 1, 5);
    _bits(ncode - 4, 4);
    for (var i = 0; i < ncode; i++) {
      _bits(clLens[codeLengthOrder[i]], 3);
    }
    final clCodes = canonicalCodes(clLens);
    for (var i = 0; i < header.length; i++) {
      final sym = header.symbols[i];
      _bits(clCodes[sym], clLens[sym]);
      switch (sym) {
        case 16:
          _bits(header.extras[i], 2);
        case 17:
          _bits(header.extras[i], 3);
        case 18:
          _bits(header.extras[i], 7);
      }
    }
    _symbols(
      lit,
      dist,
      count,
      canonicalCodes(litLens),
      litLens,
      canonicalCodes(distLens),
      distLens,
    );
  }

  void _symbols(
    Uint16List lit,
    Uint16List dist,
    int count,
    Uint16List litCodes,
    Uint8List litLens,
    Uint16List distCodes,
    Uint8List distLens,
  ) {
    for (var i = 0; i < count; i++) {
      final d = dist[i];
      final v = lit[i];
      if (d == 0) {
        _bits(litCodes[v], litLens[v]);
        continue;
      }
      final lc = _lengthCode[v];
      _bits(litCodes[257 + lc], litLens[257 + lc]);
      final le = lengthExtra[lc];
      if (le > 0) _bits(v - lengthBase[lc], le);
      final dc = _distCode(d);
      _bits(distCodes[dc], distLens[dc]);
      final de = distExtra[dc];
      if (de > 0) _bits(d - distBase[dc], de);
    }
    _bits(litCodes[256], litLens[256]);
  }
}

/// The run-length coded code lengths of a dynamic block header (symbols 0-15
/// are lengths; 16 repeats the last one, 17 and 18 repeat zero).
class _CodeLengthRuns {
  final freq = Int32List(19);
  final symbols = <int>[];
  final extras = <int>[];

  int get length => symbols.length;

  void _emit(int sym, [int extra = 0]) {
    symbols.add(sym);
    extras.add(extra);
    freq[sym]++;
  }

  /// The first [n] of [lens]. The literal and distance lengths are coded
  /// separately, as zlib does, so no run crosses between them.
  void add(Uint8List lens, int n) {
    var i = 0;
    while (i < n) {
      final len = lens[i];
      var run = 1;
      while (i + run < n && lens[i + run] == len) {
        run++;
      }
      i += run;
      if (len == 0) {
        while (run >= 11) {
          final r = run > 138 ? 138 : run;
          _emit(18, r - 11);
          run -= r;
        }
        if (run >= 3) {
          _emit(17, run - 3);
          run = 0;
        }
      } else {
        _emit(len);
        run--;
        while (run >= 3) {
          final r = run > 6 ? 6 : run;
          _emit(16, r - 3);
          run -= r;
        }
      }
      for (; run > 0; run--) {
        _emit(len);
      }
    }
  }
}

/// zlib's settings per level: [good] — a match this long already cuts the
/// search to a quarter; [lazy] — at levels 1-3 the longest match whose
/// positions are still hashed, at 4-9 the length above which no lazy
/// search is tried; [nice] — stop at a match this long; [chain] — most
/// candidates looked at.
class _Level {
  const _Level(
    this.good,
    this.lazy,
    this.nice,
    this.chain, {
    this.greedy = false,
  });

  final int good, lazy, nice, chain;
  final bool greedy;
}

const List<_Level> _levels = [
  _Level(0, 0, 0, 0),
  _Level(4, 4, 8, 4, greedy: true),
  _Level(4, 5, 16, 8, greedy: true),
  _Level(4, 6, 32, 32, greedy: true),
  _Level(4, 4, 16, 16),
  _Level(8, 16, 32, 32),
  _Level(8, 16, 128, 128),
  _Level(8, 32, 128, 256),
  _Level(32, 128, 258, 1024),
  _Level(32, 258, 258, 4096),
];

const int _minMatch = 3;
const int _maxMatch = 258;

/// Farthest distance looked back. The hash chains live in a 32 KiB ring, so
/// a candidate exactly 32768 back would share its slot with the current
/// position.
const int _maxDist = 32767;

/// A three-byte match farther back than this costs more than its literals.
const int _tooFar = 4096;

const int _hashBits = 15;
const int _hashMask = (1 << _hashBits) - 1;
const int _windowMask = 32767;

/// Symbols per block before it is written out.
const int _blockSymbols = 16384;

/// LZ77 over the whole input, handing blocks of symbols to [Deflater._block].
class _Matcher {
  _Matcher(this.out, this.input, this.level);

  final Deflater out;
  final Uint8List input;
  final _Level level;

  final Int32List _head = Int32List(1 << _hashBits)
    ..fillRange(0, 1 << _hashBits, -1);
  final Int32List _prev = Int32List(_windowMask + 1);

  final Uint16List _lit = Uint16List(_blockSymbols);
  final Uint16List _dist = Uint16List(_blockSymbols);
  final Int32List _litFreq = Int32List(286);
  final Int32List _distFreq = Int32List(30);
  int _count = 0;
  int _blockStart = 0;
  int _blockEnd = 0;

  /// Distance of the match [_longest] last found.
  int _matchDist = 0;

  void run() {
    if (level.greedy) {
      _greedy();
    } else {
      _lazy();
    }
    _flush(true);
  }

  // -- Symbols ----------------------------------------------------------------

  void _literal(int b) {
    _lit[_count] = b;
    _dist[_count] = 0;
    _litFreq[b]++;
    _blockEnd++;
    if (++_count == _blockSymbols) _flush(false);
  }

  void _match(int len, int dist) {
    _lit[_count] = len;
    _dist[_count] = dist;
    _litFreq[257 + _lengthCode[len]]++;
    _distFreq[_distCode(dist)]++;
    _blockEnd += len;
    if (++_count == _blockSymbols) _flush(false);
  }

  void _flush(bool last) {
    out._block(
      input,
      _blockStart,
      _blockEnd,
      _lit,
      _dist,
      _count,
      _litFreq,
      _distFreq,
      last,
    );
    _count = 0;
    _blockStart = _blockEnd;
    _litFreq.fillRange(0, 286, 0);
    _distFreq.fillRange(0, 30, 0);
  }

  // -- Matching ---------------------------------------------------------------

  /// Hashes the four bytes at [pos] (three at the very end of the input)
  /// into the chains; returns the previous position with the same hash, or
  /// -1.
  ///
  /// Four rather than stock zlib's three: in tile data most three-byte
  /// strings are zeros, and their one long chain hides the matches worth
  /// finding. Matches of exactly three bytes, which save little, are mostly
  /// given up; every candidate is still checked byte by byte.
  int _insert(int pos) {
    final d = input;
    final h = pos + 3 < d.length
        ? ((d[pos] << 9) ^
                  (d[pos + 1] << 6) ^
                  (d[pos + 2] << 3) ^
                  d[pos + 3] ^
                  (d[pos] >> 5)) &
              _hashMask
        : ((d[pos] << 10) ^ (d[pos + 1] << 5) ^ d[pos + 2]) & _hashMask;
    final candidate = _head[h];
    _prev[pos & _windowMask] = candidate;
    _head[h] = pos;
    return candidate;
  }

  /// The longest match at [pos] longer than [best], starting the chain at
  /// [candidate]; its distance goes to [_matchDist]. Returns [best] if none.
  int _longest(int pos, int candidate, int best) {
    final data = input;
    final max = data.length - pos < _maxMatch ? data.length - pos : _maxMatch;
    if (max <= best) return best;
    final nice = level.nice < max ? level.nice : max;
    var chain = best >= level.good ? level.chain >> 2 : level.chain;
    final limit = pos - _maxDist;
    var c = candidate;
    while (c >= 0 && c >= limit && chain-- > 0) {
      if (data[c + best] == data[pos + best] &&
          data[c] == data[pos] &&
          data[c + 1] == data[pos + 1]) {
        var len = 2;
        while (len < max && data[c + len] == data[pos + len]) {
          len++;
        }
        if (len > best) {
          best = len;
          _matchDist = pos - c;
          if (len >= nice) break;
        }
      }
      final next = _prev[c & _windowMask];
      // Chains only ever lead back; a slot reused by a newer position ends
      // this one.
      if (next >= c) break;
      c = next;
    }
    return best;
  }

  /// zlib's deflate_fast: take the longest match at each position.
  void _greedy() {
    final n = input.length;
    var pos = 0;
    while (pos < n) {
      var len = 0;
      if (n - pos >= _minMatch) {
        final candidate = _insert(pos);
        if (candidate >= 0 && pos - candidate <= _maxDist) {
          len = _longest(pos, candidate, _minMatch - 1);
        }
      }
      if (len >= _minMatch) {
        _match(len, _matchDist);
        if (len <= level.lazy) {
          for (var p = pos + 1; p < pos + len && n - p >= _minMatch; p++) {
            _insert(p);
          }
        }
        pos += len;
      } else {
        _literal(input[pos]);
        pos++;
      }
    }
  }

  /// zlib's deflate_slow: before taking a match, see whether the next
  /// position starts a longer one.
  void _lazy() {
    final n = input.length;
    var prevLen = _minMatch - 1;
    var prevDist = 0;
    var pending = false;
    var pos = 0;
    while (pos < n) {
      var len = _minMatch - 1;
      var dist = 0;
      if (n - pos >= _minMatch) {
        final candidate = _insert(pos);
        if (candidate >= 0 &&
            prevLen < level.lazy &&
            pos - candidate <= _maxDist) {
          // Only a match longer than the one one position back matters.
          len = _longest(pos, candidate, prevLen);
          if (len > prevLen) {
            dist = _matchDist;
            if (len == _minMatch && dist > _tooFar) len = _minMatch - 1;
          }
        }
      }
      if (prevLen >= _minMatch && len <= prevLen) {
        // The match found one position back wins; it started at pos - 1.
        final end = pos - 1 + prevLen;
        _match(prevLen, prevDist);
        for (var p = pos + 1; p < end && n - p >= _minMatch; p++) {
          _insert(p);
        }
        pos = end;
        pending = false;
        prevLen = _minMatch - 1;
      } else {
        if (pending) _literal(input[pos - 1]);
        pending = true;
        prevLen = len;
        prevDist = dist;
        pos++;
      }
    }
    if (pending) _literal(input[pos - 1]);
  }
}

/// Length (3-258) to its length code minus 257.
final Uint8List _lengthCode = () {
  final t = Uint8List(_maxMatch + 1);
  for (var code = 0; code < 29; code++) {
    for (
      var l = lengthBase[code];
      l < lengthBase[code] + (1 << lengthExtra[code]) && l <= _maxMatch;
      l++
    ) {
      t[l] = code;
    }
  }
  return t;
}();

/// Distance - 1 to its distance code: below 256 directly, above by 128s.
final Uint8List _distCodes = () {
  final t = Uint8List(512);
  for (var code = 0; code < 30; code++) {
    final lo = distBase[code] - 1;
    for (var d = lo; d < lo + (1 << distExtra[code]); d++) {
      if (d < 256) {
        t[d] = code;
      } else {
        t[256 + (d >> 7)] = code;
      }
    }
  }
  return t;
}();

int _distCode(int dist) {
  final d = dist - 1;
  return d < 256 ? _distCodes[d] : _distCodes[256 + (d >> 7)];
}

final Uint16List _fixedLiteral = canonicalCodes(fixedLiteralLengths);
final Uint16List _fixedDistance = canonicalCodes(fixedDistanceLengths);
