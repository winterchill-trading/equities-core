open! Core
open Equities_core
module Price = Exchange_core.Price

let p = Price.of_string

let ny h m s =
  Time_ns.add
    (Session.Zone.of_local New_york (Date.of_string "2026-10-12") (Session.hm h m))
    (Time_ns.Span.of_int_sec s)
;;

let%expect_test "LULD widths" =
  List.iter [ "100"; "3.01"; "3"; "0.75"; "0.5"; "0.1" ] ~f:(fun r ->
    List.iter Halts.Tier.all ~f:(fun tier ->
      printf
        "%-5s %s width=%s\n"
        r
        (Sexp.to_string (Halts.Tier.sexp_of_t tier))
        (Price.to_string (Halts.luld_width tier ~reference:(p r)))));
  [%expect
    {|
    100   Tier1 width=5
    100   Tier2 width=10
    3.01  Tier1 width=0.1505
    3.01  Tier2 width=0.301
    3     Tier1 width=0.6
    3     Tier2 width=0.6
    0.75  Tier1 width=0.15
    0.75  Tier2 width=0.15
    0.5   Tier1 width=0.15
    0.5   Tier2 width=0.15
    0.1   Tier1 width=0.075
    0.1   Tier2 width=0.075
    |}]
;;

let%expect_test "band doubling windows" =
  let show label tier reference at =
    print_s
      [%message
        label ~_:(Halts.luld_bands tier ~reference:(p reference) ~at : Halts.Bands.t)]
  in
  show "tier1 10:00" Tier1 "100" (ny 10 0 0);
  show "tier1 15:35" Tier1 "100" (ny 15 35 0);
  show "tier2 15:35" Tier2 "100" (ny 15 35 0);
  show "tier2 low 15:35" Tier2 "2" (ny 15 35 0);
  show "tier1 09:31" Tier1 "100" (ny 9 31 0);
  print_s
    [%message
      "tier1 09:31 legacy"
        ~_:
          (Halts.luld_bands
             ~double_at_open:true
             Tier1
             ~reference:(p "100")
             ~at:(ny 9 31 0)
           : Halts.Bands.t)];
  show "rounded" Tier1 "3.01" (ny 10 0 0);
  [%expect
    {|
    ("tier1 10:00" ((lower 95) (upper 105)))
    ("tier1 15:35" ((lower 90) (upper 110)))
    ("tier2 15:35" ((lower 90) (upper 110)))
    ("tier2 low 15:35" ((lower 1.2) (upper 2.8)))
    ("tier1 09:31" ((lower 95) (upper 105)))
    ("tier1 09:31 legacy" ((lower 90) (upper 110)))
    (rounded ((lower 2.86) (upper 3.16)))
    |}]
;;

let show_state (state : Halts.Luld.state) =
  let t x = Session.to_local_string New_york x in
  match state with
  | Normal -> "normal"
  | Limit_state { at_upper; since } ->
    sprintf
      "limit state at %s band since %s"
      (if at_upper then "upper" else "lower")
      (t since)
  | Paused { until } -> sprintf "paused until %s" (t until)
;;

let%expect_test "limit state, exit and pause" =
  let bands = { Halts.Bands.lower = p "95"; upper = p "105" } in
  let t = Halts.Luld.create () in
  let quote s bid offer =
    Halts.Luld.on_quote
      t
      ~now:(ny 11 0 s)
      ~bands
      ~best_bid:(Some (p bid))
      ~best_offer:(Some (p offer));
    printf "%02d: %s\n" s (show_state (Halts.Luld.state t))
  in
  quote 0 "99" "100";
  quote 1 "105" "105.01";
  quote 5 "104.9" "105";
  quote 10 "105" "105.02";
  quote 25 "105" "105.02";
  print_s [%message "" ~trade_ok:(Halts.Luld.trade_allowed t ~bands (p "104") : bool)];
  Halts.Luld.tick t ~now:(ny 11 5 25);
  printf "after pause: %s\n" (show_state (Halts.Luld.state t));
  [%expect
    {|
    00: normal
    01: limit state at upper band since 2026-10-12 11:00:01
    05: normal
    10: limit state at upper band since 2026-10-12 11:00:10
    25: paused until 2026-10-12 11:05:25
    (trade_ok false)
    after pause: normal
    |}]
;;

let%expect_test "market-wide circuit breakers" =
  let t = Halts.Circuit_breaker.create ~prior_close:(p "6000") in
  let feed label at value =
    let lvl = Halts.Circuit_breaker.on_index t ~now:at (p value) in
    print_s
      [%message
        label
          ~fired:(lvl : Halts.Circuit_breaker.Level.t option)
          ~halted:(Halts.Circuit_breaker.is_halted t ~now:at : bool)]
  in
  feed "10:00 -6.9%" (ny 10 0 0) "5586";
  feed "10:00 -7%" (ny 10 0 0) "5580";
  feed "10:10 again" (ny 10 10 0) "5570";
  feed "10:15 resume" (ny 10 15 0) "5575";
  feed "15:30 -13%" (ny 15 30 0) "5220";
  feed "15:40 -20%" (ny 15 40 0) "4800";
  print_s [%sexp (Halts.Circuit_breaker.triggered t : Halts.Circuit_breaker.Level.t list)];
  [%expect
    {|
    ("10:00 -6.9%" (fired ()) (halted false))
    ("10:00 -7%" (fired (Level1)) (halted true))
    ("10:10 again" (fired ()) (halted true))
    ("10:15 resume" (fired ()) (halted false))
    ("15:30 -13%" (fired (Level2)) (halted false))
    ("15:40 -20%" (fired (Level3)) (halted true))
    (Level1 Level2 Level3)
    |}]
;;
