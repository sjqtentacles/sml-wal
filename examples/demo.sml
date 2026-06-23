(* demo.sml

   A tour of `sml-wal`: build a write-ahead log as a pure value, inspect its
   deterministic on-disk framing, checkpoint (compact) it, and show that the
   strict decoder rejects a corrupted tail. Everything here is pure -- no IO
   beyond the final `print`s -- so the output is byte-identical under MLton and
   Poly/ML.

   Build and run with `make example`. *)

structure W = Wal

fun line s = print (s ^ "\n")

(* Render a string as space-separated two-hex-digit bytes, for showing the
   exact framing in a compiler-independent way. *)
fun toHex s =
  String.concatWith " "
    (List.map
       (fn c =>
          let val h = Int.fmt StringCvt.HEX (Char.ord c)
          in if String.size h = 1 then "0" ^ h else h end)
       (String.explode s))

fun showEntries label w =
  let
    val es = W.entries w
    fun go (_, []) = ()
      | go (i, e :: rest) =
          (line ("  [" ^ Int.toString i ^ "] " ^ e); go (i + 1, rest))
  in
    line (label ^ " (" ^ Int.toString (List.length es) ^ " entries)");
    go (0, es)
  end

val () = line "=== sml-wal demo =============================================="
val () = line ""

(* ---- build a log by appending three records ---- *)
val log =
  W.append (W.append (W.append W.empty "SET x=1") "SET y=2") "DEL x"
val () = showEntries "Built log" log
val () = line ""

(* ---- deterministic framing ---- *)
val enc = W.encode log
val () = line ("Encoded " ^ Int.toString (String.size enc) ^ " bytes "
               ^ "(4-byte BE length + payload + 4-byte BE CRC32 per record):")
val () = line ("  " ^ toHex enc)
val () = line ""

(* ---- recovery via replay ---- *)
val () = line "Replay (decode then entries):"
val () = List.app (fn e => line ("  " ^ e)) (W.replay enc)
val () = line ""

(* ---- checkpoint / compaction ---- *)
val compacted = W.checkpoint log 2
val () = showEntries "After checkpoint (drop oldest 2)" compacted
val () = line ("  re-encodes to " ^ Int.toString (String.size (W.encode compacted))
               ^ " bytes; byte-identical to a fresh log of the survivors: "
               ^ Bool.toString (W.encode compacted = W.encode (W.append W.empty "DEL x")))
val () = line ""

(* ---- strict corruption detection ---- *)
val () = line "Corruption detection (strict decode):"
(* flip the last payload byte; its stored CRC no longer matches. *)
val flipped =
  let
    val i = String.size enc - 5  (* a payload byte, just before the 4-byte CRC *)
    val c' = Char.chr ((Char.ord (String.sub (enc, i)) + 1) mod 256)
  in
    String.substring (enc, 0, i) ^ String.str c' ^ String.extract (enc, i + 1, NONE)
  end
val crcResult =
  (ignore (W.decode flipped); "  UNEXPECTED: decoded corrupted stream")
  handle W.Corrupt m => "  rejected flipped byte -> Corrupt \"" ^ m ^ "\""
val () = line crcResult

(* drop the final byte: the last record's CRC trailer is now truncated. *)
val truncated = String.substring (enc, 0, String.size enc - 1)
val truncResult =
  (ignore (W.decode truncated); "  UNEXPECTED: decoded truncated stream")
  handle W.Corrupt m => "  rejected truncated tail -> Corrupt \"" ^ m ^ "\""
val () = line truncResult
val () = line ""
val () = line "==============================================================="
