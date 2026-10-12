open! Core
open Equities_core
module Equity = Symbol.Equity
module Future = Symbol.Future
module Osi = Symbol.Osi

let%expect_test "equity tickers" =
  List.iter
    [ "AAPL"
    ; "BRK.B"
    ; "BRK B"
    ; "BAC PRL"
    ; "BAC.PR"
    ; "XYZ.WSA"
    ; "ABC.RT"
    ; "SPAC U"
    ; "XYZ.WI"
    ; "TOOLONG"
    ; "aapl"
    ; "BRK.ZZZ"
    ; ""
    ]
    ~f:(fun s ->
      match Equity.of_string s with
      | Ok t ->
        printf
          "%-8S nyse=%-8S compact=%-8S test=%b\n"
          s
          (Equity.to_nyse t)
          (Equity.to_compact t)
          (Equity.is_test t)
      | Error e -> printf "%-8S error %s\n" s (Error.to_string_hum e));
  print_s [%sexp (Equity.of_string "ZVZZT" |> Or_error.ok_exn |> Equity.is_test : bool)];
  [%expect
    {|
    "AAPL"   nyse="AAPL"   compact="AAPL"   test=false
    "BRK.B"  nyse="BRK B"  compact="BRK.B"  test=false
    "BRK B"  nyse="BRK B"  compact="BRK.B"  test=false
    "BAC PRL" nyse="BAC PRL" compact="BAC.PRL" test=false
    "BAC.PR" nyse="BAC PR" compact="BAC.PR" test=false
    "XYZ.WSA" nyse="XYZ WSA" compact="XYZ.WSA" test=false
    "ABC.RT" nyse="ABC RT" compact="ABC.RT" test=false
    "SPAC U" nyse="SPAC U" compact="SPAC.U" test=false
    "XYZ.WI" nyse="XYZ WI" compact="XYZ.WI" test=false
    "TOOLONG" error ("invalid ticker root" TOOLONG)
    "aapl"   error ("invalid ticker root" aapl)
    "BRK.ZZZ" error ("invalid ticker suffix" BRK.ZZZ)
    ""       error ("invalid ticker root" "")
    true
    |}]
;;

let%expect_test "futures codes and expiries" =
  List.iter [ "ESZ6"; "ESH7"; "NQM26"; "CLZ6"; "GCZ6"; "ESZ5"; "ESA6"; "Z6" ] ~f:(fun s ->
    match Future.of_string ~reference_year:2026 s with
    | Error e -> printf "%s error %s\n" s (Error.to_string_hum e)
    | Ok t ->
      print_s
        [%message
          s
            ~parsed:(t : Future.t)
            ~code:(Future.to_string t)
            ~last_trade:(Future.last_trade_date t : Date.t Or_error.t)]);
  [%expect
    {|
    (ESZ6 (parsed ((root ES) (month Dec) (year 2026))) (code ESZ6)
     (last_trade (Ok 2026-12-18)))
    (ESH7 (parsed ((root ES) (month Mar) (year 2027))) (code ESH7)
     (last_trade (Ok 2027-03-19)))
    (NQM26 (parsed ((root NQ) (month Jun) (year 2026))) (code NQM6)
     (last_trade (Ok 2026-06-19)))
    (CLZ6 (parsed ((root CL) (month Dec) (year 2026))) (code CLZ6)
     (last_trade (Ok 2026-11-20)))
    (GCZ6 (parsed ((root GC) (month Dec) (year 2026))) (code GCZ6)
     (last_trade (Ok 2026-12-29)))
    (ESZ5 (parsed ((root ES) (month Dec) (year 2035))) (code ESZ5)
     (last_trade (Ok 2035-12-21)))
    ESA6 error ("invalid futures month code" ESA6)
    Z6 error ("invalid futures code" Z6)
    |}]
;;

let%expect_test "crude oil rule when the 25th is a weekend" =
  (* 2026-04-25 is a Saturday: four business days before it. *)
  let t = { Future.root = "CL"; month = May; year = 2026 } in
  print_s [%sexp (Future.last_trade_date t : Date.t Or_error.t)];
  [%expect {| (Ok 2026-04-21) |}]
;;

let%expect_test "front quarterly contract rolls after expiry" =
  List.iter [ "2026-10-12"; "2026-12-18"; "2026-12-19" ] ~f:(fun d ->
    let t = Future.front_quarterly ~root:"ES" (Date.of_string d) |> Or_error.ok_exn in
    printf "%s -> %s\n" d (Future.to_string t));
  [%expect {|
    2026-10-12 -> ESZ6
    2026-12-18 -> ESZ6
    2026-12-19 -> ESH7
    |}]
;;

let%expect_test "month codes" =
  print_endline (String.of_char_list (List.map Month.all ~f:Future.Month_code.of_month));
  [%expect {| FGHJKMNQUVXZ |}]
;;

let%expect_test "OSI symbols" =
  List.iter
    [ "SPY   261218C00600000"
    ; "AAPL  270115P00172500"
    ; "BRKB  261120C00450500"
    ; "SPY   261218X00600000"
    ; "SPY 261218C00600000"
    ; "SPY   261318C00600000"
    ]
    ~f:(fun s ->
      match Osi.of_string s with
      | Error e -> printf "%S error %s\n" s (Error.to_string_hum e)
      | Ok t ->
        print_s [%message (t : Osi.t)];
        assert (String.equal (Osi.to_string t) s));
  [%expect
    {|
    (t ((root SPY) (expiry 2026-12-18) (right Call) (strike 600)))
    (t ((root AAPL) (expiry 2027-01-15) (right Put) (strike 172.5)))
    (t ((root BRKB) (expiry 2026-11-20) (right Call) (strike 450.5)))
    "SPY   261218X00600000" error ("invalid OSI right" "SPY   261218X00600000")
    "SPY 261218C00600000" error ("OSI symbol must be 21 characters" "SPY 261218C00600000")
    "SPY   261318C00600000" error (Failure "Month.of_int_exn 13")
    |}]
;;
