# Changelog

## [0.1.0] - 2026-10-06

### Added

- **ZlibCodec**, **GzipCodec** and **DeflateCodec**: `encode(List<int>)` and `decode(List<int>, {maxOutputSize})` for zlib (RFC 1950), gzip (RFC 1952) and raw DEFLATE (RFC 1951) data.
  - Compression levels 0-9 with zlib's settings: stored blocks at 0, greedy matching at 1-3, lazy matching at 4-9. Each block is written stored, fixed-Huffman or dynamic-Huffman, whichever is smallest.
  - The match finder hashes four bytes rather than zlib's three, which matters for tile data, where most three-byte strings are zeros. Output sizes are within a few bytes of `dart:io`'s zlib at every level.
  - Output is identical on native, web and Wasm.
  - The decoder reads every block type and any window size. Adler-32 and CRC-32 checksums are verified. Gzip files may hold several members and gzip's optional header fields (FEXTRA, FNAME, FCOMMENT, FHCRC).
  - Damaged data throws `FormatException`, never another error. `maxOutputSize` caps the decoded size.
- **adler32** and **crc32** checksums, each able to continue a running value.
- Tests: round trips at every level for every format, both ways against `dart:io`'s zlib (every level, window size, memory level and strategy), real zlib output kept as fixtures, hand-built bad streams, every truncation, and seeded random damage. They run on the VM, dart2js and dart2wasm.
