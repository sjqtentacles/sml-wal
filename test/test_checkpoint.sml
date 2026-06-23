(* test_checkpoint.sml -- compaction drops the right prefix and re-encodes.

   `checkpoint w n` drops the oldest `n` live entries. The dropped prefix must
   vanish from `entries`, the tail must be untouched and in order, and the
   re-encoded log must equal a freshly-built log of just the surviving
   entries (so a checkpointed log is byte-identical to one that never held the
   dropped entries). *)

structure CheckpointTests =
struct
  open Support
  structure W = Wal

  val full = ["a", "b", "c", "d", "e"]
  val log = ofList full

  fun run () =
    let
      val () = Harness.section "checkpoint drops the oldest prefix"
      val () = Harness.checkStringList "drop 0 = no-op"
                 (full, W.entries (W.checkpoint log 0))
      val () = Harness.checkStringList "drop 2 keeps [c,d,e]"
                 (["c", "d", "e"], W.entries (W.checkpoint log 2))
      val () = Harness.checkStringList "drop all = empty"
                 ([], W.entries (W.checkpoint log 5))

      val () = Harness.section "checkpoint clamps out-of-range n"
      val () = Harness.checkStringList "negative n = no-op"
                 (full, W.entries (W.checkpoint log ~3))
      val () = Harness.checkStringList "n > length = empty"
                 ([], W.entries (W.checkpoint log 99))

      val () = Harness.section "compaction re-encodes canonically"
      (* a checkpointed log encodes identically to a fresh log of the tail. *)
      val () = Harness.checkString "encode (checkpoint log 2) = encode (fresh [c,d,e])"
                 (W.encode (ofList ["c", "d", "e"]),
                  W.encode (W.checkpoint log 2))
      (* round-trips through encode/decode after compaction. *)
      val () = Harness.checkStringList "replay (encode (checkpoint log 2))"
                 (["c", "d", "e"], W.replay (W.encode (W.checkpoint log 2)))

      val () = Harness.section "checkpoint then append"
      val cont = W.append (W.checkpoint log 3) "f"
      val () = Harness.checkStringList "drop 3 then append f"
                 (["d", "e", "f"], W.entries cont)
      val () = Harness.checkString "compacted+appended encodes canonically"
                 (W.encode (ofList ["d", "e", "f"]), W.encode cont)
    in
      ()
    end
end
