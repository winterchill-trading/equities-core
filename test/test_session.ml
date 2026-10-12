open! Core
open Equities_core
module S = Session

let ny y m d h mi = S.Zone.of_local New_york (Date.create_exn ~y ~m ~d) (S.hm h mi)
let ct y m d h mi = S.Zone.of_local Chicago (Date.create_exn ~y ~m ~d) (S.hm h mi)
let utc t = Time_ns.to_string_utc t

let%expect_test "daylight saving boundaries in New York" =
  List.iter
    [ ny 2026 Mar 8 1 59; ny 2026 Mar 8 3 0; ny 2026 Nov 1 0 30; ny 2026 Nov 1 3 0 ]
    ~f:(fun t ->
      printf
        "%s local = %s utc, dst=%b\n"
        (S.to_local_string New_york t)
        (utc t)
        (S.Zone.is_dst New_york t));
  [%expect
    {|
    2026-03-08 01:59:00 local = 2026-03-08 06:59:00.000000000Z utc, dst=false
    2026-03-08 03:00:00 local = 2026-03-08 07:00:00.000000000Z utc, dst=true
    2026-11-01 00:30:00 local = 2026-11-01 04:30:00.000000000Z utc, dst=true
    2026-11-01 03:00:00 local = 2026-11-01 08:00:00.000000000Z utc, dst=false
    |}]
;;

let%expect_test "spring gap moves forward" =
  print_endline (S.to_local_string New_york (ny 2026 Mar 8 2 30));
  [%expect {| 2026-03-08 03:30:00 |}]
;;

let%expect_test "equities phases on a regular day" =
  List.iter
    [ 3, 59; 4, 0; 9, 29; 9, 30; 15, 59; 16, 0; 19, 59; 20, 0 ]
    ~f:(fun (h, m) ->
      printf
        "%02d:%02d %s\n"
        h
        m
        (Sexp.to_string
           (S.Us_equities.Phase.sexp_of_t (S.Us_equities.phase_at (ny 2026 Oct 12 h m)))));
  [%expect
    {|
    03:59 Closed
    04:00 Pre_market
    09:29 Pre_market
    09:30 Core
    15:59 Core
    16:00 Post_market
    19:59 Post_market
    20:00 Closed
    |}]
;;

let%expect_test "holidays, weekends and early closes" =
  List.iter
    [ 2026, Month.Jul, 3; 2026, Jul, 4; 2026, Nov, 27; 2026, Dec, 24; 2026, Dec, 28 ]
    ~f:(fun (y, m, d) ->
      let date = Date.create_exn ~y ~m ~d in
      print_s
        [%message
          ""
            (date : Date.t)
            ~day:(S.Us_equities.day date : S.Us_equities.Day.t)
            ~at_13_30:(S.Us_equities.phase_at (ny y m d 13 30) : S.Us_equities.Phase.t)
            ~at_17_30:(S.Us_equities.phase_at (ny y m d 17 30) : S.Us_equities.Phase.t)]);
  [%expect
    {|
    ((date 2026-07-03) (day (Holiday "Independence Day (observed)"))
     (at_13_30 Closed) (at_17_30 Closed))
    ((date 2026-07-04) (day Weekend) (at_13_30 Closed) (at_17_30 Closed))
    ((date 2026-11-27) (day (Early_close "Day after Thanksgiving"))
     (at_13_30 Post_market) (at_17_30 Closed))
    ((date 2026-12-24) (day (Early_close "Christmas Eve")) (at_13_30 Post_market)
     (at_17_30 Closed))
    ((date 2026-12-28) (day Regular) (at_13_30 Core) (at_17_30 Post_market))
    |}]
;;

let%expect_test "trading days in 2026" =
  let days =
    List.init 365 ~f:(fun i -> Date.add_days (Date.create_exn ~y:2026 ~m:Jan ~d:1) i)
    |> List.count ~f:(fun d -> S.Us_equities.is_trading_day d)
  in
  print_s
    [%message
      (days : int) ~years:(S.Us_equities.years_covered S.Us_equities.nyse_2026 : int list)];
  print_endline
    (Date.to_string
       (S.Us_equities.next_trading_day (Date.create_exn ~y:2026 ~m:Jul ~d:2)));
  [%expect {|
    ((days 251) (years (2026)))
    2026-07-06
    |}]
;;

let%expect_test "core open and close instants in UTC" =
  let o, c =
    Option.value_exn
      (S.Us_equities.core_open_close (Date.create_exn ~y:2026 ~m:Dec ~d:24))
  in
  printf "%s %s\n" (utc o) (utc c);
  [%expect {| 2026-12-24 14:30:00.000000000Z 2026-12-24 18:00:00.000000000Z |}]
;;

let%expect_test "CME Globex week" =
  List.iter
    [ "Sun 16:59", ct 2026 Oct 11 16 59
    ; "Sun 17:00", ct 2026 Oct 11 17 0
    ; "Mon 15:59", ct 2026 Oct 12 15 59
    ; "Mon 16:30", ct 2026 Oct 12 16 30
    ; "Mon 17:00", ct 2026 Oct 12 17 0
    ; "Fri 15:59", ct 2026 Oct 16 15 59
    ; "Fri 16:00", ct 2026 Oct 16 16 0
    ; "Sat 12:00", ct 2026 Oct 17 12 0
    ]
    ~f:(fun (label, t) ->
      print_s
        [%message
          label
            ~phase:(S.Cme_globex.phase_at t : S.Cme_globex.Phase.t)
            ~trade_date:(S.Cme_globex.trade_date t : Date.t option)]);
  [%expect
    {|
    ("Sun 16:59" (phase Closed) (trade_date ()))
    ("Sun 17:00" (phase Open) (trade_date (2026-10-12)))
    ("Mon 15:59" (phase Open) (trade_date (2026-10-12)))
    ("Mon 16:30" (phase Maintenance) (trade_date ()))
    ("Mon 17:00" (phase Open) (trade_date (2026-10-13)))
    ("Fri 15:59" (phase Open) (trade_date (2026-10-16)))
    ("Fri 16:00" (phase Closed) (trade_date ()))
    ("Sat 12:00" (phase Closed) (trade_date ()))
    |}]
;;
