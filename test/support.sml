(* support.sml -- shared helpers for the sml-wal tests.

   The WAL is a pure value over byte-in-string framing, so unlike a numeric
   library every check is exact: structural string / string-list equality is
   the right comparison and is identical under MLton and Poly/ML. These helpers
   just make the byte-level framing tests readable -- building 4-byte big-endian
   length/CRC fields and hand-assembling records to feed `decode`. *)

structure Support =
struct
  (* A 4-byte big-endian field from a Word32 (the on-wire field type). We work
     in Word32 throughout rather than going via `int`, because MLton's default
     `Int` is only 32 bits, so `Word32.toInt` of a value with the high bit set
     (a CRC, typically) raises `Overflow`. Poly/ML's `Int` is 63-bit and would
     not (both defaults are fixed-width -- only `IntInf` is arbitrary precision),
     so staying in Word32 keeps the tests identical across both compilers. *)
  fun be32w (w : Word32.word) : string =
    let
      fun byte k =
        Char.chr (Word32.toInt (Word32.andb (Word32.>> (w, k), 0wxFF)))
    in
      String.implode [byte 0w24, byte 0w16, byte 0w8, byte 0w0]
    end

  (* Convenience for small (length) fields given as an int. *)
  fun be32 (n : int) : string = be32w (Word32.fromInt n)

  (* Hand-assemble one framed record (length + payload + given 4-byte crc),
     letting tests inject an arbitrary/wrong CRC. *)
  fun frame (payload, crcField) =
    be32 (String.size payload) ^ payload ^ crcField

  (* The 4-byte CRC field that Wal would emit for `payload`. *)
  fun crcField payload = be32w (Wal.crc32 payload)

  (* A correctly-checksummed record for `payload`. *)
  fun goodRecord payload = frame (payload, crcField payload)

  (* Build a log from a list of payloads, oldest first. *)
  fun ofList xs = List.foldl (fn (x, w) => Wal.append w x) Wal.empty xs
end
