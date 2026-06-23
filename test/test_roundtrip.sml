(* test_roundtrip.sml -- append / encode / decode / replay round-trips.

   The core contract: building a log by `append`, then `encode`, `decode`, and
   `replay`, recovers exactly the entries in order; and re-encoding a decoded
   log is byte-identical (idempotence of the encode/decode pair). *)

structure RoundtripTests =
struct
  open Support
  structure W = Wal

  val msgs = ["alpha", "bravo", "charlie", "delta"]

  fun run () =
    let
      val () = Harness.section "empty log"
      val () = Harness.checkStringList "entries empty = []" ([], W.entries W.empty)
      val () = Harness.checkString "encode empty = \"\"" ("", W.encode W.empty)
      val () = Harness.checkStringList "replay \"\" = []" ([], W.replay "")
      val () = Harness.checkStringList "decode (encode empty) = []"
                 ([], W.entries (W.decode (W.encode W.empty)))

      val () = Harness.section "append order"
      val log = ofList msgs
      val () = Harness.checkStringList "entries preserve append order"
                 (msgs, W.entries log)
      val () = Harness.checkStringList "append is left-to-right"
                 (["x", "y"], W.entries (W.append (W.append W.empty "x") "y"))

      val () = Harness.section "encode / decode / replay round-trip"
      val enc = W.encode log
      val () = Harness.checkStringList "decode (encode w) = entries w"
                 (msgs, W.entries (W.decode enc))
      val () = Harness.checkStringList "replay (encode w) = entries w"
                 (msgs, W.replay enc)
      val () = Harness.checkString "encode (decode (encode w)) = encode w"
                 (enc, W.encode (W.decode enc))

      val () = Harness.section "payload edge cases"
      (* empty payloads are legal records (length 0). *)
      val () = Harness.checkStringList "empty-string entries survive"
                 (["", "x", ""], W.replay (W.encode (ofList ["", "x", ""])))
      (* arbitrary bytes incl. NUL and high bytes round-trip. *)
      val binary = String.implode (List.map Char.chr [0, 1, 255, 10, 13, 0, 127])
      val () = Harness.checkStringList "binary payload round-trips"
                 ([binary], W.replay (W.encode (ofList [binary])))
      (* a payload that itself looks like framing must not confuse the decoder. *)
      val tricky = be32 99 ^ "not a real record"
      val () = Harness.checkStringList "framing-shaped payload round-trips"
                 ([tricky], W.replay (W.encode (ofList [tricky])))
    in
      ()
    end
end
