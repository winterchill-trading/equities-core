open! Core
open Equities_core
module O = Order_types
module Price = Exchange_core.Price

let p = Price.of_string

let show t =
  match O.validate t with
  | Ok () -> print_endline "ok"
  | Error e ->
    (match Error.sexp_of_t e with
     | List (_ :: reasons :: _) -> print_s reasons
     | s -> print_s s)
;;

let%expect_test "valid orders" =
  List.iter
    [ O.create Buy ~qty:100 ~limit:(p "10.01")
    ; O.create Sell_short ~qty:1 ~limit:(p "0.5123") ~tif:Ioc
    ; O.create Buy ~qty:300 (* market day *)
    ; O.moo Buy ~qty:500
    ; O.loc Sell ~qty:500 ~limit:(p "20")
    ; { (O.create Buy ~qty:1000 ~limit:(p "5")) with
        display = Reserve { display_qty = 200 }
      ; stp = Cancel_newest
      }
    ; { (O.create Buy ~qty:1000 ~limit:(p "5") ~tif:Gtc) with post_only = true }
    ]
    ~f:show;
  [%expect {|
    ok
    ok
    ok
    ok
    ok
    ok
    ok
    |}]
;;

let%expect_test "invalid orders" =
  List.iter
    [ O.create Buy ~qty:0 ~limit:(p "10")
    ; O.create Buy ~qty:100 ~limit:(p "10.001")
    ; { (O.create Buy ~qty:100) with post_only = true }
    ; O.create Buy ~qty:100 ~tif:Gtc
    ; { (O.moc Sell ~qty:100) with display = Hidden }
    ; { (O.create Buy ~qty:100 ~limit:(p "10") ~tif:Fok) with post_only = true }
    ; { (O.create Buy ~qty:1000 ~limit:(p "5")) with
        display = Reserve { display_qty = 150 }
      }
    ; { (O.create Buy ~qty:100 ~limit:(p "5")) with min_qty = Some 200 }
    ]
    ~f:show;
  [%expect
    {|
    ("quantity must be positive")
    ("limit price must be positive and on the tick")
    ("market orders must be visible, not post-only, not ISO and not GTC")
    ("market orders must be visible, not post-only, not ISO and not GTC")
    ("market orders must be visible, not post-only, not ISO and not GTC"
     "auction orders must be visible without post-only, ISO or minimum quantity")
    ("IOC and FOK orders cannot be post-only or reserve")
    ("reserve display quantity must be a round lot multiple below the order quantity")
    ("minimum quantity must be between 1 and the order quantity")
    |}]
;;

let%expect_test "auction kinds" =
  List.iter
    [ O.moo Buy ~qty:1
    ; O.loo Buy ~qty:1 ~limit:(p "1")
    ; O.moc Sell ~qty:1
    ; O.loc Sell ~qty:1 ~limit:(p "1")
    ; O.create Buy ~qty:1
    ]
    ~f:(fun t -> print_s [%sexp (O.auction_kind t : Auction.Order_kind.t option)]);
  [%expect {|
    (Moo)
    (Loo)
    (Moc)
    (Loc)
    ()
    |}]
;;

let%expect_test "mapping onto the engine" =
  let symbol = Exchange_core.Symbol.of_string "AAPL" in
  List.iter
    [ O.create Buy ~qty:100 ~limit:(p "190.25")
    ; { (O.create Sell_short ~qty:100 ~limit:(p "190.30")) with post_only = true }
    ; O.create Sell ~qty:50 ~tif:Ioc
    ; O.create Buy ~qty:100 ~limit:(p "190") ~tif:Fok
    ; { (O.create Buy ~qty:100 ~limit:(p "190")) with display = Hidden }
    ]
    ~f:(fun t ->
      match O.to_order_request t ~symbol with
      | Ok r ->
        print_s
          [%message
            ""
              ~side:(r.side : Exchange_core.Side.t)
              ~size:(Exchange_core.Size.to_string r.size)
              ~px:(Option.map r.px ~f:Price.to_string : string option)
              ~order_type:(r.order_type : Exchange_core.Order_type.t)]
      | Error e ->
        (match Error.sexp_of_t e with
         | List (msg :: what :: _) -> print_s (List [ msg; what ])
         | s -> print_s s));
  [%expect
    {|
    ((side Buy) (size 100) (px (190.25)) (order_type (Limit Gtc)))
    ((side Sell) (size 100) (px (190.3)) (order_type (Limit Alo)))
    ((side Sell) (size 50) (px ()) (order_type (Market (slippage_bps ()))))
    ("not supported by the engine" "time in force")
    ("not supported by the engine" "hidden or reserve display")
    |}]
;;

let%expect_test "Rule 201 short sale restriction" =
  let d = Date.of_string in
  let prev_close = p "100" in
  let ssr = O.Ssr.inactive in
  let ssr = O.Ssr.on_trade ssr ~date:(d "2026-11-25") ~prev_close ~price:(p "90.01") in
  print_s [%message "after 90.01" ~through:(O.Ssr.restricted_through ssr : Date.t option)];
  let ssr = O.Ssr.on_trade ssr ~date:(d "2026-11-25") ~prev_close ~price:(p "90") in
  print_s [%message "after 90.00" ~through:(O.Ssr.restricted_through ssr : Date.t option)];
  List.iter [ "2026-11-25"; "2026-11-27"; "2026-11-30" ] ~f:(fun date ->
    let date = d date in
    let allows side price =
      O.Ssr.allows ssr ~date ~side ~price:(p price) ~national_best_bid:(p "89.50")
    in
    print_s
      [%message
        ""
          (date : Date.t)
          ~active:(O.Ssr.is_active ssr ~date : bool)
          ~short_at_bid:(allows Sell_short "89.50" : bool)
          ~short_above_bid:(allows Sell_short "89.51" : bool)
          ~exempt_at_bid:(allows Sell_short_exempt "89.50" : bool)]);
  [%expect
    {|
    ("after 90.01" (through ()))
    ("after 90.00" (through (2026-11-27)))
    ((date 2026-11-25) (active true) (short_at_bid false) (short_above_bid true)
     (exempt_at_bid true))
    ((date 2026-11-27) (active true) (short_at_bid false) (short_above_bid true)
     (exempt_at_bid true))
    ((date 2026-11-30) (active false) (short_at_bid true) (short_above_bid true)
     (exempt_at_bid true))
    |}]
;;
