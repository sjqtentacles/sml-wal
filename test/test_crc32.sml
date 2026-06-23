(* test_crc32.sml -- the CRC-32 (IEEE) primitive against known vectors.

   Reference values are the standard CRC-32/ISO-HDLC check values widely
   published (zlib, RFC 1952): crc32("") = 0x00000000, and the canonical
   check string "123456789" hashes to 0xCBF43926. A couple of short ASCII
   inputs are pinned to zlib-computed values. *)

structure Crc32Tests =
struct
  open Support

  fun hx w = Word32.fmt StringCvt.HEX w

  fun run () =
    let
      val () = Harness.section "crc32 known vectors"
      val () = Harness.checkString "crc32 \"\" = 0"
                 ("0", hx (Wal.crc32 ""))
      val () = Harness.checkString "crc32 \"123456789\" = CBF43926"
                 ("CBF43926", hx (Wal.crc32 "123456789"))
      val () = Harness.checkString "crc32 \"a\" = E8B7BE43"
                 ("E8B7BE43", hx (Wal.crc32 "a"))
      val () = Harness.checkString "crc32 \"abc\" = 352441C2"
                 ("352441C2", hx (Wal.crc32 "abc"))
      val () = Harness.checkString "crc32 \"The quick brown fox jumps over the lazy dog\" = 414FA339"
                 ("414FA339",
                  hx (Wal.crc32 "The quick brown fox jumps over the lazy dog"))

      val () = Harness.section "crc32 determinism"
      val () = Harness.check "crc32 is a pure function"
                 (Wal.crc32 "hello" = Wal.crc32 "hello")
      val () = Harness.check "distinct inputs differ"
                 (Wal.crc32 "hello" <> Wal.crc32 "world")
    in
      ()
    end
end
