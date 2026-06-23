(* test_determinism.sml -- encode is a deterministic function of the log value.

   The encoding must depend only on the *logical* sequence of live entries,
   never on how that sequence was built (append history, checkpoints) or on
   the run/machine/compiler. Two logs with equal `entries` must `encode` to
   byte-identical strings, and the framing layout must be exactly as
   documented (4-byte BE length + payload + 4-byte BE CRC). *)

structure DeterminismTests =
struct
  open Support
  structure W = Wal

  fun run () =
    let
      val () = Harness.section "encode depends only on live entries"
      (* built directly vs. via an over-long log that was checkpointed down. *)
      val direct = ofList ["c", "d", "e"]
      val viaCheckpoint = W.checkpoint (ofList ["a", "b", "c", "d", "e"]) 2
      val () = Harness.checkString "same entries => same bytes (history-free)"
                 (W.encode direct, W.encode viaCheckpoint)
      (* re-running encode yields the identical string. *)
      val () = Harness.checkString "encode is referentially transparent"
                 (W.encode direct, W.encode direct)

      val () = Harness.section "exact byte layout (single record)"
      (* one entry "hi": length 2 BE + "hi" + crc32("hi") BE. *)
      val rec1 = W.encode (ofList ["hi"])
      val () = Harness.checkInt "record size = 4 + 2 + 4" (10, String.size rec1)
      val () = Harness.checkString "length prefix is 4-byte BE 2"
                 (be32 2, String.substring (rec1, 0, 4))
      val () = Harness.checkString "payload sits after the length"
                 ("hi", String.substring (rec1, 4, 2))
      val () = Harness.checkString "trailer is 4-byte BE crc32(payload)"
                 (crcField "hi", String.substring (rec1, 6, 4))

      val () = Harness.section "total size is additive across records"
      (* sizes: ""->4+0+4=8, "ab"->4+2+4=10, "abc"->4+3+4=11 => 29. *)
      val three = W.encode (ofList ["", "ab", "abc"])
      val () = Harness.checkInt "concatenated record sizes" (29, String.size three)
    in
      ()
    end
end
