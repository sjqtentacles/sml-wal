(* wal.sml

   Implementation of `WAL` as an opaque structure `Wal`. A log value is just
   the ordered list of live entry payloads -- there is no mutable state, no IO,
   no clock, no randomness, no FFI, and no threads. Every operation is a pure
   function returning a new value.

   Byte-level care for cross-compiler determinism:
     - All checksum arithmetic is done in `Word32` (exactly 32 bits) so MLton
       and Poly/ML agree regardless of the native `Word` width.
     - Bytes are read/written via `Char.chr`/`Char.ord` on a `string`, treating
       one `char` as one 8-bit byte (the Basis guarantees `Char.maxOrd = 255`
       on both compilers).
     - The CRC-32 lookup table is built once at structure-initialization time
       from the reflected IEEE polynomial 0xEDB88320; the result is a pure
       constant, identical on every run. *)

structure Wal :> WAL =
struct
  (* A log is its live entries, oldest first. *)
  type t = string list

  exception Corrupt of string

  val empty : t = []

  fun append w payload = w @ [payload]

  fun entries (w : t) = w

  fun checkpoint w n =
    if n <= 0 then w
    else List.drop (w, Int.min (n, List.length w))

  (* ---- CRC-32 (IEEE 802.3, reflected, poly 0xEDB88320) ---- *)

  val poly : Word32.word = 0wxEDB88320

  (* Per-byte table entry: fold the 8 shifts of the reflected algorithm. *)
  fun mkEntry n =
    let
      fun step (0, c) = c
        | step (k, c) =
            let
              val c' =
                if Word32.andb (c, 0w1) = 0w1
                then Word32.xorb (Word32.>> (c, 0w1), poly)
                else Word32.>> (c, 0w1)
            in step (k - 1, c') end
    in
      step (8, Word32.fromInt n)
    end

  val table : Word32.word vector = Vector.tabulate (256, mkEntry)

  (* CRC-32 with the conventional init/xorout of 0xFFFFFFFF. *)
  fun crc32 (s : string) : Word32.word =
    let
      val n = String.size s
      fun loop (i, crc) =
        if i >= n then crc
        else
          let
            val b = Word32.fromInt (Char.ord (String.sub (s, i)))
            val idx = Word32.toInt (Word32.andb (Word32.xorb (crc, b), 0wxFF))
            val crc' =
              Word32.xorb (Word32.>> (crc, 0w8), Vector.sub (table, idx))
          in loop (i + 1, crc') end
    in
      Word32.xorb (loop (0, 0wxFFFFFFFF), 0wxFFFFFFFF)
    end

  (* ---- big-endian 32-bit (de)serialization ---- *)

  fun putW32 (w : Word32.word) : string =
    let
      fun byte k =
        Char.chr (Word32.toInt (Word32.andb (Word32.>> (w, k), 0wxFF)))
    in
      String.implode [byte 0w24, byte 0w16, byte 0w8, byte 0w0]
    end

  (* Read a big-endian Word32 at offset `off`; caller guarantees 4 bytes. *)
  fun getW32 (s, off) : Word32.word =
    let
      fun b k =
        Word32.<< (Word32.fromInt (Char.ord (String.sub (s, off + k))),
                   Word.fromInt (8 * (3 - k)))
    in
      Word32.orb (Word32.orb (b 0, b 1), Word32.orb (b 2, b 3))
    end

  (* ---- framing ---- *)

  fun encodeRecord payload =
    putW32 (Word32.fromInt (String.size payload)) ^ payload ^ putW32 (crc32 payload)

  fun encode (w : t) =
    String.concat (List.map encodeRecord w)

  (* Strict decode: walk records front-to-back, raising `Corrupt` on any
     framing shortfall or CRC mismatch (so a truncated tail is rejected, not
     dropped). Entries are accumulated in order. *)
  fun decode s =
    let
      val total = String.size s
      fun loop (off, acc) =
        if off = total then List.rev acc
        else if off + 4 > total then
          raise Corrupt "truncated record header (need 4-byte length)"
        else
          let
            (* Compare the declared length against the bytes that remain while
               still in Word32: on MLton `Int` is 32-bit, so a crafted huge
               length would make `Word32.toInt` raise `Overflow` instead of our
               own `Corrupt`. `remaining` (bytes after the 4-byte header) is a
               small non-negative int, so widening it to Word32 is safe. *)
            val lenW = getW32 (s, off)
            val remaining = Word32.fromInt (total - (off + 4))
          in
            if Word32.> (lenW, remaining) then
              raise Corrupt "truncated payload (length exceeds remaining bytes)"
            else
            let
              val len = Word32.toInt lenW  (* now known <= remaining, fits Int *)
              val payOff = off + 4
              val crcOff = payOff + len
              val nextOff = crcOff + 4
            in
              if nextOff > total then
                raise Corrupt "truncated record (missing 4-byte CRC trailer)"
              else
                let
                  val payload = String.substring (s, payOff, len)
                  val stored = getW32 (s, crcOff)
                  val actual = crc32 payload
                in
                  if stored <> actual then
                    raise Corrupt "CRC mismatch (record corrupted)"
                  else loop (nextOff, payload :: acc)
                end
            end
          end
    in
      loop (0, [])
    end

  fun replay s = entries (decode s)
end
