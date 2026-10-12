open! Core
open Equities_core
module Price = Exchange_core.Price

let p = Price.of_string

let order id side kind ?limit qty =
  { Auction.Order.id; side; qty; kind; limit = Option.map limit ~f:p }
;;

(* A textbook opening book. Cumulative interest:

   price buy sell matched imbalance 9.98 1000 400 400 600 buy 10.00 1000 400 400 600 buy
   10.01 600 400 400 200 buy (reference) 10.02 600 700 600 100 sell 10.03 600 700 600 100
   sell 10.04 300 900 300 600 sell 10.05 300 900 300 600 sell

   Volume is maximal (600) at 10.02 and 10.03 with the same imbalance; 10.02 is closer to
   the reference price 10.01. *)
let book =
  [ order 1 Buy Moo 100
  ; order 2 Buy Loo ~limit:"10.05" 200
  ; order 3 Buy Book ~limit:"10.03" 300
  ; order 4 Buy Book ~limit:"10.00" 400
  ; order 5 Sell Moo 150
  ; order 6 Sell Loo ~limit:"9.98" 250
  ; order 7 Sell Book ~limit:"10.02" 300
  ; order 8 Sell Book ~limit:"10.04" 200
  ; order 9 Buy Moc 5000
  ]
;;

let%expect_test "opening auction clearing price" =
  print_s
    [%sexp
      (Auction.clearing ~kind:Opening ~reference:(p "10.01") book
       : Auction.Result.t option)];
  [%expect
    {|
    (((price 10.02) (matched 600) (buy_qty 600) (sell_qty 700) (imbalance 100)
      (imbalance_side (Sell))))
    |}]
;;

let%expect_test "allocation follows price then time priority" =
  let r, fills =
    Option.value_exn (Auction.uncross ~kind:Opening ~reference:(p "10.01") book)
  in
  print_s [%message (r.price : Price.t) (fills : Auction.Fill.t list)];
  [%expect
    {|
    ((r.price 10.02)
     (fills
      (((id 1) (side Buy) (qty 100) (price 10.02))
       ((id 2) (side Buy) (qty 200) (price 10.02))
       ((id 3) (side Buy) (qty 300) (price 10.02))
       ((id 5) (side Sell) (qty 150) (price 10.02))
       ((id 6) (side Sell) (qty 250) (price 10.02))
       ((id 7) (side Sell) (qty 200) (price 10.02)))))
    |}]
;;

let%expect_test "imbalance at the reference price" =
  print_s
    [%sexp
      (Auction.imbalance ~kind:Opening ~reference:(p "10.01") book : Auction.Imbalance.t)];
  [%expect
    {|
    ((kind Opening) (reference_price 10.01) (paired_qty 400) (imbalance_qty 200)
     (imbalance_side (Buy)) (market_imbalance_qty 50) (indicative_price (10.02))
     (indicative_matched 600))
    |}]
;;

let%expect_test "reference price wins inside a flat range" =
  (* Any price from 20.00 to 20.10 matches 500 with no imbalance. *)
  let orders =
    [ order 1 Buy Loc ~limit:"20.10" 500; order 2 Sell Loc ~limit:"20.00" 500 ]
  in
  List.iter [ "20.05"; "19.50"; "21" ] ~f:(fun reference ->
    let r =
      Option.value_exn (Auction.clearing ~kind:Closing ~reference:(p reference) orders)
    in
    printf "reference %s -> %s\n" reference (Price.to_string r.price));
  [%expect
    {|
    reference 20.05 -> 20.05
    reference 19.50 -> 20
    reference 21 -> 20.1
    |}]
;;

let%expect_test "market orders only clear at the reference price" =
  let orders = [ order 1 Buy Moc 300; order 2 Sell Moc 200 ] in
  print_s
    [%sexp
      (Auction.uncross ~kind:Closing ~reference:(p "50") orders
       : (Auction.Result.t * Auction.Fill.t list) option)];
  [%expect
    {|
    ((((price 50) (matched 200) (buy_qty 300) (sell_qty 200) (imbalance 100)
       (imbalance_side (Buy)))
      (((id 1) (side Buy) (qty 200) (price 50))
       ((id 2) (side Sell) (qty 200) (price 50)))))
    |}]
;;

let%expect_test "no cross, no auction trade" =
  let orders =
    [ order 1 Buy Book ~limit:"9.99" 100; order 2 Sell Book ~limit:"10.01" 100 ]
  in
  print_s
    [%sexp
      (Auction.clearing ~kind:Halt_reopening ~reference:(p "10") orders
       : Auction.Result.t option)];
  [%expect {| () |}]
;;

let%expect_test "order kinds and validation" =
  List.iter Auction.Order_kind.all ~f:(fun k ->
    print_s
      [%message
        ""
          ~_:(k : Auction.Order_kind.t)
          ~auctions:
            (List.filter Auction.Kind.all ~f:(Auction.Order_kind.participates k)
             : Auction.Kind.t list)]);
  print_s
    [%sexp (Auction.Order.validate (order 1 Buy Moo ~limit:"1" 100) : unit Or_error.t)];
  [%expect
    {|
    (Moo (auctions (Opening)))
    (Loo (auctions (Opening)))
    (Moc (auctions (Closing)))
    (Loc (auctions (Closing)))
    (Book (auctions (Opening Closing Halt_reopening)))
    (Error
     ("limit price presence does not match order kind"
      (t ((id 1) (side Buy) (qty 100) (kind Moo) (limit (1))))))
    |}]
;;
