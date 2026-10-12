open! Core
module Price = Exchange_core.Price

let default_round_lot = 100

let round_lot_for_price px =
  if Price.( <= ) px (Price.of_int 250)
  then 100
  else if Price.( <= ) px (Price.of_int 1_000)
  then 40
  else if Price.( <= ) px (Price.of_int 10_000)
  then 10
  else 1
;;

module Kind = struct
  type t =
    | Round
    | Odd
    | Mixed
  [@@deriving sexp, compare, equal, enumerate]
end

let classify ?(round_lot = default_round_lot) qty =
  if qty <= 0
  then raise_s [%message "Lot.classify: quantity must be positive" (qty : int)];
  if qty < round_lot then Kind.Odd else if qty % round_lot = 0 then Round else Mixed
;;

let split ?(round_lot = default_round_lot) qty =
  let odd = qty % round_lot in
  qty - odd, odd
;;

let round_lots ?(round_lot = default_round_lot) qty = qty / round_lot

module Contract = struct
  let unit_description (p : Tick_size.Cme_product.t) =
    sprintf "%d %s" p.multiplier p.unit_of_measure
  ;;

  let notional (p : Tick_size.Cme_product.t) ~price ~contracts =
    Tick_size.Cme_product.pnl p ~price_change:price ~contracts
  ;;

  let validate_quantity ?(max = 10_000) qty =
    if qty <= 0
    then error_s [%message "contract quantity must be positive" (qty : int)]
    else if qty > max
    then error_s [%message "contract quantity above maximum" (qty : int) (max : int)]
    else Ok ()
  ;;
end
