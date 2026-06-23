(* test_framing.sml -- strict decode: truncation and CRC-mismatch rejection.

   `decode` is documented to *reject* (raise `Wal.Corrupt`) rather than
   silently drop a damaged tail. We exercise:
     - a truncated final record (payload cut short of its declared length),
     - a missing/short 4-byte CRC trailer,
     - a header that over-claims its length,
     - a flipped payload byte (CRC mismatch),
     - a corrupted stored CRC field. *)

structure FramingTests =
struct
  open Support
  structure W = Wal

  fun run () =
    let
      val good = W.encode (ofList ["one", "two", "three"])

      val () = Harness.section "well-formed framing decodes"
      val () = Harness.checkStringList "sanity: good stream replays"
                 (["one", "two", "three"], W.replay good)
      (* hand-assembled records agree with encode (the framing is what we test). *)
      val handmade = goodRecord "one" ^ goodRecord "two" ^ goodRecord "three"
      val () = Harness.checkString "hand-framed = encode" (good, handmade)

      val () = Harness.section "truncated tail is rejected"
      (* drop the final byte: the last CRC trailer is now short. *)
      val cutCrc = String.substring (good, 0, String.size good - 1)
      val () = Harness.checkRaises "short final CRC raises"
                 (fn () => W.decode cutCrc)
      (* a record header claiming 5 bytes but only 2 follow. *)
      val cutPayload = be32 5 ^ "ab"
      val () = Harness.checkRaises "payload shorter than length raises"
                 (fn () => W.decode cutPayload)
      (* header itself truncated to < 4 bytes. *)
      val () = Harness.checkRaises "sub-header trailing bytes raise"
                 (fn () => W.decode (good ^ "\000\000"))
      (* a valid first record followed by a truncated second is still rejected,
         and is NOT silently treated as a one-entry log. *)
      val partial = goodRecord "alpha" ^ be32 10 ^ "short"
      val () = Harness.checkRaises "good record + truncated record raises"
                 (fn () => W.decode partial)

      val () = Harness.section "CRC mismatch is rejected"
      (* flip a payload byte but keep the original (now wrong) CRC. *)
      val bad = frame ("XXX", crcField "one")  (* CRC of "one", payload "XXX" *)
      val () = Harness.checkRaises "payload/CRC mismatch raises"
                 (fn () => W.decode bad)
      (* keep the payload, corrupt the stored CRC field. *)
      val badCrc = frame ("one", be32 0)
      val () = Harness.checkRaises "wrong stored CRC raises"
                 (fn () => W.decode badCrc)

      val () = Harness.section "Corrupt carries a message"
      val raisedMsg =
        (W.decode badCrc; "")
        handle W.Corrupt m => m | _ => "wrong-exn"
      val () = Harness.check "Corrupt message is non-empty"
                 (raisedMsg <> "" andalso raisedMsg <> "wrong-exn")
    in
      ()
    end
end
