open! Core
open Equities_core
module Price = Exchange_core.Price

let%expect_test "lot kinds" =
  List.iter [ 1; 99; 100; 250; 300 ] ~f:(fun q ->
    print_s
      [%message
        ""
          ~qty:(q : int)
          ~kind:(Lot.classify q : Lot.Kind.t)
          ~split:(Lot.split q : int * int)
          ~lots:(Lot.round_lots q : int)]);
  print_s [%message "" ~with_lot_40:(Lot.classify ~round_lot:40 120 : Lot.Kind.t)];
  [%expect
    {|
    ((qty 1) (kind Odd) (split (0 1)) (lots 0))
    ((qty 99) (kind Odd) (split (0 99)) (lots 0))
    ((qty 100) (kind Round) (split (100 0)) (lots 1))
    ((qty 250) (kind Mixed) (split (200 50)) (lots 2))
    ((qty 300) (kind Round) (split (300 0)) (lots 3))
    (with_lot_40 Round)
    |}]
;;

let%expect_test "price tiered round lots" =
  List.iter [ "10"; "250"; "250.01"; "1000"; "4000"; "10000.01" ] ~f:(fun s ->
    printf "%s -> %d\n" s (Lot.round_lot_for_price (Price.of_string s)));
  [%expect
    {|
    10 -> 100
    250 -> 100
    250.01 -> 40
    1000 -> 40
    4000 -> 10
    10000.01 -> 1
    |}]
;;

let%expect_test "contracts" =
  List.iter Tick_size.Cme_product.all ~f:(fun p ->
    printf "%s: %s\n" p.root (Lot.Contract.unit_description p));
  print_endline
    (Exchange_core.Usd.to_string
       (Lot.Contract.notional
          Tick_size.Cme_product.es
          ~price:(Price.of_string "5800.25")
          ~contracts:2));
  print_s
    [%message
      ""
        ~zero:(Lot.Contract.validate_quantity 0 : unit Or_error.t)
        ~one:(Lot.Contract.validate_quantity 1 : unit Or_error.t)];
  [%expect
    {|
    ES: 50 USD per index point
    NQ: 20 USD per index point
    CL: 1000 barrels
    GC: 100 troy ounces
    580025
    ((zero (Error ("contract quantity must be positive" (qty 0)))) (one (Ok ())))
    |}]
;;
