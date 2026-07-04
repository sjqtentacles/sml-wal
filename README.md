# sml-wal

[![CI](https://github.com/sjqtentacles/sml-wal/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-wal/actions/workflows/ci.yml)

A write-ahead log (WAL) in pure Standard ML, modeled as a **pure value** — no
IO, no clock, no randomness, no FFI, no threads anywhere. A `Wal.t` is just the
ordered list of live entry payloads; every operation returns a new value, like
a persistent data structure. Durability is expressed purely as the
serialization pair `encode`/`decode` over `string`s (one `char` = one byte), so
the caller decides when and how the bytes touch a real device.

No external dependencies — Basis library only — and **deterministic,
byte-identically** under both [MLton](http://mlton.org/) and
[Poly/ML](https://www.polyml.org/). The same logical log always `encode`s to the
exact same bytes on every run, machine, and compiler.

## Status

- 44 assertions, green on MLton and Poly/ML.
- Basis-library only; no `require` block, no vendored dependencies (Layout A,
  standalone).
- Pure: no FFI, no IO, no clock, no randomness, no threads.

## Install

With [`smlpkg`](https://github.com/diku-dk/smlpkg):

```
smlpkg add github.com/sjqtentacles/sml-wal
smlpkg sync
```

Include the MLB from your own:

```
local
  $(SML_LIB)/basis/basis.mlb
  lib/github.com/sjqtentacles/sml-wal/src/wal.mlb (via smlpkg)
in
  ...
end
```

This brings `structure Wal` into scope.

## Quick start

```sml
(* a log is a pure value: append returns a new log *)
val log = Wal.append (Wal.append (Wal.append Wal.empty "SET x=1") "SET y=2") "DEL x"
val es  = Wal.entries log                 (* ["SET x=1","SET y=2","DEL x"] *)

(* deterministic, self-describing framing packed into a string *)
val bytes = Wal.encode log                (* 4B length + payload + 4B CRC32, per record *)

(* recovery: decode (inverse of encode) or replay (decode then entries) *)
val log' = Wal.decode bytes               (* Wal.t, entries restored in order *)
val es'  = Wal.replay bytes               (* same as Wal.entries (Wal.decode bytes) *)

(* compaction: drop the oldest n entries (clamped) *)
val tail = Wal.checkpoint log 2           (* keeps just ["DEL x"] *)

(* strict decode rejects a damaged tail or a CRC mismatch *)
val ok = (Wal.decode (String.substring (bytes, 0, String.size bytes - 1)); false)
         handle Wal.Corrupt _ => true     (* true: truncated trailer rejected *)
```

## API (`signature WAL`)

```sml
type t
exception Corrupt of string

val empty      : t
val crc32      : string -> Word32.word     (* IEEE 802.3, reflected, init/xorout 0xFFFFFFFF *)
val append     : t -> string -> t          (* add a payload (raw bytes) as the newest entry *)
val entries    : t -> string list          (* all live entries, oldest first *)
val checkpoint : t -> int -> t             (* drop the oldest n entries (clamped) *)
val encode     : t -> string               (* deterministic length-prefixed + CRC32 framing *)
val decode     : string -> t               (* inverse of encode; raises Corrupt on bad framing *)
val replay     : string -> string list     (* decode then entries *)
```

### On-disk framing

`encode` writes each entry as one record and concatenates them in log order,
with no surrounding header or trailer:

```
+----------------+------------------+----------------+
| length (4 BE)  | payload (length) | crc32 (4 BE)   |
+----------------+------------------+----------------+
```

- **length** — payload size in bytes, 4-byte big-endian unsigned.
- **payload** — the raw entry bytes (may be empty; may contain NULs / high
  bytes; may even look like framing — it round-trips regardless).
- **crc32** — CRC-32 (IEEE 802.3 polynomial `0xEDB88320`, reflected,
  init/xorout `0xFFFFFFFF`) of the **payload bytes only**, 4-byte big-endian.

The layout depends solely on the logical sequence of live entries, never on how
that sequence was built (append history, checkpoints). So `encode (decode s) =
s` for any `s` produced by `encode`, and two logs with equal `entries` `encode`
to byte-identical strings.

### Error handling — truncated tails are *rejected*

`decode` (and therefore `replay`) is **strict**: it raises `Corrupt` rather than
silently dropping a damaged record. It rejects

- a **truncated final record** — a payload shorter than its declared length, or
  a missing/short 4-byte CRC trailer (e.g. a write cut off mid-record), and
- a **CRC mismatch** — a payload or stored checksum that disagree.

A cut-off final record therefore raises `Corrupt` (it is *not* ignored or
returned as a partial log), so a half-written tail can never be mistaken for a
committed entry.

### Conventions

- `append w s` adds `s` as the **newest** entry; `entries` is **oldest first**.
- `checkpoint w n` clamps `n`: `n <= 0` is a no-op, `n >=` the length yields
  `empty`. A checkpointed log re-`encode`s identically to a fresh log of just
  the survivors.
- `crc32` is exposed so callers can verify records by hand; it is the same
  function used for the framing trailer.

### Cross-compiler byte semantics

All checksum and field arithmetic is done in **`Word32`** (exactly 32 bits), not
via `int`. This matters because MLton's default `Int` is **32-bit**, so
`Word32.toInt` of a value with the high bit set (a CRC, typically) raises
`Overflow`, whereas Poly/ML's `Int` is 63-bit and holds it. (Both defaults are
fixed-width — 32-bit MLton, 63-bit Poly/ML; only `IntInf` is arbitrary
precision.) Staying in `Word32`
— and bounds-checking a record's declared length against the remaining bytes
*before* narrowing it to `int` — keeps `encode`/`decode` byte-identical and
makes a crafted oversized length surface as `Corrupt` (not `Overflow`) on both
compilers.

## Build & test

```
make test        # MLton
make test-poly   # Poly/ML
make all-tests   # both
make example     # build + run examples/demo.sml
make clean
```

Both compilers run the same strict-TDD suite (44 assertions), pinned to exact
byte vectors rather than tolerances:

- **CRC-32 known vectors** — the standard check values (`crc32 "" = 0`,
  `crc32 "123456789" = 0xCBF43926`, plus short ASCII strings computed by zlib).
- **Round-trip** — `append`/`encode`/`decode`/`replay` recover entries in order,
  including empty payloads, binary payloads (NUL / high bytes), and payloads
  that themselves look like framing; `encode (decode (encode w)) = encode w`.
- **Strict framing** — a truncated tail (short payload, missing CRC trailer,
  sub-header bytes, or a good record followed by a cut-off one) and a CRC
  mismatch (flipped payload byte or corrupted stored CRC) all raise `Corrupt`.
- **Checkpoint** — compaction drops the right prefix, clamps out-of-range `n`,
  and re-encodes byte-identically to a fresh log of the survivors.
- **Determinism** — `encode` depends only on the live entries (history-free),
  is referentially transparent, and matches the documented byte layout exactly.

## Example

`make example` builds a small log, dumps its exact framing as hex, replays it,
checkpoints it, and shows the strict decoder rejecting a flipped byte and a
truncated tail (output is byte-identical under MLton and Poly/ML):

```
=== sml-wal demo ==============================================

Built log (3 entries)
  [0] SET x=1
  [1] SET y=2
  [2] DEL x

Encoded 43 bytes (4-byte BE length + payload + 4-byte BE CRC32 per record):
  00 00 00 07 53 45 54 20 78 3D 31 DC B1 00 D2 00 00 00 07 53 45 54 20 79 3D 32 44 7A 3B 5F 00 00 00 05 44 45 4C 20 78 75 41 08 93

Replay (decode then entries):
  SET x=1
  SET y=2
  DEL x

After checkpoint (drop oldest 2) (1 entries)
  [0] DEL x
  re-encodes to 13 bytes; byte-identical to a fresh log of the survivors: true

Corruption detection (strict decode):
  rejected flipped byte -> Corrupt "CRC mismatch (record corrupted)"
  rejected truncated tail -> Corrupt "truncated record (missing 4-byte CRC trailer)"

===============================================================
```

### Poly/ML note

CI builds Poly/ML 5.9.1 from source rather than using the Ubuntu package
(Poly/ML 5.7.1), whose X86 code generator can crash (`asGenReg raised while
compiling`) on some code. See `.github/workflows/ci.yml`.

## License

MIT — see [LICENSE](LICENSE).
