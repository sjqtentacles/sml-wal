(* wal.sig

   A write-ahead log (WAL) modeled as a *pure value* -- no IO, no clock, no
   randomness, no FFI, no threads anywhere. A `Wal.t` is just the ordered list
   of live entry payloads; every operation returns a new value, exactly like a
   persistent data structure (cf. `sml-kv`). Persistence/recovery is expressed
   purely as the (de)serialization pair `encode`/`decode` over `string`s, so
   the caller decides when and how the bytes hit a real device.

   ---- on-disk framing ----------------------------------------------------

   `encode` produces a deterministic, self-describing byte stream packed into a
   `string` (one `char` = one byte). Each entry is written as a record:

       +----------------+------------------+----------------+
       | length (4 BE)  | payload (length) | crc32 (4 BE)   |
       +----------------+------------------+----------------+

     - `length` is the payload size in bytes as a 4-byte big-endian unsigned
       integer.
     - `payload` is the raw entry bytes.
     - `crc32` is the CRC-32 (IEEE 802.3 polynomial 0xEDB88320, reflected,
       init/xorout 0xFFFFFFFF) of the *payload bytes only*, as a 4-byte
       big-endian unsigned integer.

   Records are concatenated in log order with no header or trailer, so the
   encoding of a given logical log is byte-identical on every run, machine, and
   compiler (MLton and Poly/ML alike). `encode (decode s) = s` for any `s`
   produced by `encode`, and `decode (encode w)` recovers `w`'s entries.

   ---- error handling -----------------------------------------------------

   `decode` is strict. It raises `Corrupt` on any framing error:
     - a record header that claims more payload bytes than remain in the input
       (a *truncated tail* -- e.g. a write that was cut off mid-record), or
     - a missing/short 4-byte CRC trailer, or
     - a CRC that does not match the recomputed checksum of the payload.
   A truncated final record is therefore *rejected* (not silently dropped):
   `decode` raises rather than returning a partial log. `replay` shares this
   behavior. *)

signature WAL =
sig
  (* A write-ahead log value: the ordered live entries plus nothing else. *)
  type t

  (* Raised by `decode`/`replay` on bad framing or a CRC mismatch. *)
  exception Corrupt of string

  (* The empty log. *)
  val empty : t

  (* CRC-32 (IEEE 802.3, reflected, poly 0xEDB88320, init/xorout 0xFFFFFFFF)
     of the bytes of a string. Exposed because it defines the framing's
     trailer and is handy for callers verifying records by hand. *)
  val crc32 : string -> Word32.word

  (* `append w payload` returns `w` with `payload` (raw bytes in a string)
     added as the newest entry. *)
  val append : t -> string -> t

  (* All live entries, oldest first. *)
  val entries : t -> string list

  (* `checkpoint w n` compacts the log by dropping its oldest `n` entries
     (a clamp: `n <= 0` is a no-op, `n >=` the length yields `empty`). *)
  val checkpoint : t -> int -> t

  (* Serialize to the deterministic length-prefixed + CRC32 framing above. *)
  val encode : t -> string

  (* Inverse of `encode`. Raises `Corrupt` on any framing/CRC error,
     including a truncated final record. *)
  val decode : string -> t

  (* `decode` then `entries`: the live payloads of an encoded log. *)
  val replay : string -> string list
end
