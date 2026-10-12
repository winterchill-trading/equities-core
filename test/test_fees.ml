open! Core
open Equities_core
module Price = Exchange_core.Price
module Usd = Exchange_core.Usd

let p = Price.of_string

let%expect_test "per share schedules" =
  List.iter [ Fees.bzx_like; Fees.nyse_like ] ~f:(fun t ->
    List.iter [ "25"; "0.5" ] ~f:(fun price ->
      List.iter Fees.Liquidity.all ~f:(fun liq ->
        printf
          "%s %s %s x1000 -> %s\n"
          t.name
          (Sexp.to_string (Fees.Liquidity.sexp_of_t liq))
          price
          (Usd.to_string (Fees.fee t liq ~price:(p price) ~qty:1000)))));
  [%expect
    {|
    bzx-like Maker 25 x1000 -> -1.6
    bzx-like Taker 25 x1000 -> 3
    bzx-like Auction 25 x1000 -> 1
    bzx-like Maker 0.5 x1000 -> 0
    bzx-like Taker 0.5 x1000 -> 1.5
    bzx-like Auction 0.5 x1000 -> 1.5
    nyse-like Maker 25 x1000 -> -1.2
    nyse-like Taker 25 x1000 -> 2.75
    nyse-like Auction 25 x1000 -> 1
    nyse-like Maker 0.5 x1000 -> 0
    nyse-like Taker 0.5 x1000 -> 1.5
    nyse-like Auction 0.5 x1000 -> 1.5
    |}]
;;

let%expect_test "per contract" =
  List.iter Fees.Liquidity.all ~f:(fun liq ->
    printf
      "%s %s\n"
      (Sexp.to_string (Fees.Liquidity.sexp_of_t liq))
      (Usd.to_string (Fees.fee Fees.cme_like liq ~price:(p "5800.25") ~qty:3)));
  [%expect {|
    Maker 3
    Taker 3
    Auction 3
    |}]
;;

let%expect_test "engine basis points at a representative price" =
  print_s
    [%sexp (Fees.to_engine Fees.bzx_like ~price:(p "30") : Exchange_core.Fee_schedule.t)];
  [%expect {| ((taker_bps 1) (maker_bps 0)) |}]
;;
