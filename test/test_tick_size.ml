open! Core
open Equities_core
module Price = Exchange_core.Price

let p = Price.of_string

let%expect_test "equity ticks" =
  List.iter [ "0.5"; "0.9999"; "1"; "250.37" ] ~f:(fun s ->
    printf "%s -> %s\n" s (Price.to_string (Tick_size.equity (p s))));
  List.iter [ "0.1234"; "0.12345"; "1.001"; "1.01"; "0" ] ~f:(fun s ->
    printf "%s valid=%b\n" s (Tick_size.is_valid_equity_price (p s)));
  [%expect
    {|
    0.5 -> 0.0001
    0.9999 -> 0.0001
    1 -> 0.01
    250.37 -> 0.01
    0.1234 valid=true
    0.12345 valid=false
    1.001 valid=false
    1.01 valid=true
    0 valid=false
    |}]
;;

let%expect_test "option ticks" =
  List.iter Tick_size.Option_class.all ~f:(fun cls ->
    List.iter [ "2.99"; "3" ] ~f:(fun s ->
      print_s
        [%message
          ""
            (cls : Tick_size.Option_class.t)
            ~px:s
            ~tick:(Price.to_string (Tick_size.option cls (p s)))
            ~valid_2_97:(Tick_size.is_valid_option_price cls (p "2.97") : bool)]));
  [%expect
    {|
    ((cls Standard) (px 2.99) (tick 0.05) (valid_2_97 false))
    ((cls Standard) (px 3) (tick 0.1) (valid_2_97 false))
    ((cls Penny) (px 2.99) (tick 0.01) (valid_2_97 true))
    ((cls Penny) (px 3) (tick 0.05) (valid_2_97 true))
    ((cls Penny_all) (px 2.99) (tick 0.01) (valid_2_97 true))
    ((cls Penny_all) (px 3) (tick 0.01) (valid_2_97 true))
    |}]
;;

let%expect_test "CME tick values" =
  List.iter Tick_size.Cme_product.all ~f:(fun t ->
    printf
      "%s tick=%s x%d %s tick_value=%s\n"
      t.root
      (Price.to_string t.tick)
      t.multiplier
      t.unit_of_measure
      (Exchange_core.Usd.to_string (Tick_size.Cme_product.tick_value t)));
  let es = Option.value_exn (Tick_size.Cme_product.find "ES") in
  print_endline
    (Exchange_core.Usd.to_string
       (Tick_size.Cme_product.pnl es ~price_change:(p "-12.5") ~contracts:3));
  [%expect
    {|
    ES tick=0.25 x50 USD per index point tick_value=12.5
    NQ tick=0.25 x20 USD per index point tick_value=5
    CL tick=0.01 x1000 barrels tick_value=10
    GC tick=0.1 x100 troy ounces tick_value=10
    -1875
    |}]
;;

let%expect_test "rounding to tick" =
  let tick = p "0.25" in
  List.iter [ "5001.1"; "5001.125"; "5001.25"; "5001.13" ] ~f:(fun s ->
    printf
      "%s down=%s up=%s nearest=%s\n"
      s
      (Price.to_string (Tick_size.round ~tick `Down (p s)))
      (Price.to_string (Tick_size.round ~tick `Up (p s)))
      (Price.to_string (Tick_size.round ~tick `Nearest (p s))));
  [%expect
    {|
    5001.1 down=5001 up=5001.25 nearest=5001
    5001.125 down=5001 up=5001.25 nearest=5001.25
    5001.25 down=5001.25 up=5001.25 nearest=5001.25
    5001.13 down=5001 up=5001.25 nearest=5001.25
    |}]
;;
