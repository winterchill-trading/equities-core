open! Core
module Price = Exchange_core.Price

let p = Price.of_string
let one_dollar = p "1"
let three_dollars = p "3"
let equity px = if Price.( < ) px one_dollar then p "0.0001" else p "0.01"

module Option_class = struct
  type t =
    | Standard
    | Penny
    | Penny_all
  [@@deriving sexp, compare, equal, enumerate]
end

let option (cls : Option_class.t) px =
  let below = Price.( < ) px three_dollars in
  match cls with
  | Standard -> if below then p "0.05" else p "0.10"
  | Penny -> if below then p "0.01" else p "0.05"
  | Penny_all -> p "0.01"
;;

module Cme_product = struct
  type t =
    { root : string
    ; name : string
    ; tick : Price.t
    ; multiplier : int
    ; unit_of_measure : string
    }
  [@@deriving sexp, compare, equal]

  let es =
    { root = "ES"
    ; name = "E-mini S&P 500"
    ; tick = p "0.25"
    ; multiplier = 50
    ; unit_of_measure = "USD per index point"
    }
  ;;

  let nq =
    { root = "NQ"
    ; name = "E-mini Nasdaq-100"
    ; tick = p "0.25"
    ; multiplier = 20
    ; unit_of_measure = "USD per index point"
    }
  ;;

  let cl =
    { root = "CL"
    ; name = "Crude Oil (WTI)"
    ; tick = p "0.01"
    ; multiplier = 1000
    ; unit_of_measure = "barrels"
    }
  ;;

  let gc =
    { root = "GC"
    ; name = "Gold"
    ; tick = p "0.10"
    ; multiplier = 100
    ; unit_of_measure = "troy ounces"
    }
  ;;

  let all = [ es; nq; cl; gc ]
  let find root = List.find all ~f:(fun t -> String.equal t.root root)

  let pnl t ~price_change ~contracts =
    Exchange_core.Usd.of_units (Price.to_units price_change * t.multiplier * contracts)
  ;;

  let tick_value t = pnl t ~price_change:t.tick ~contracts:1
end

let is_on_tick ~tick px = Price.to_units px % Price.to_units tick = 0
let is_valid_equity_price px = Price.is_positive px && is_on_tick ~tick:(equity px) px

let is_valid_option_price cls px =
  Price.is_positive px && is_on_tick ~tick:(option cls px) px
;;

let round ~tick dir px =
  let u = Price.to_units px
  and t = Price.to_units tick in
  let down = u - (u % t) in
  let units =
    match dir with
    | `Down -> down
    | `Up -> if down = u then u else down + t
    | `Nearest -> if 2 * (u - down) >= t then down + t else down
  in
  Price.of_units units
;;
