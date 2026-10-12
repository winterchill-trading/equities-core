open! Core
module Price = Exchange_core.Price
module Usd = Exchange_core.Usd

module Liquidity = struct
  type t =
    | Maker
    | Taker
    | Auction
  [@@deriving sexp, compare, equal, enumerate]
end

module Unit = struct
  type t =
    | Per_share
    | Per_contract
  [@@deriving sexp, compare, equal]
end

type t =
  { name : string
  ; unit : Unit.t
  ; maker : Usd.t
  ; taker : Usd.t
  ; auction : Usd.t
  ; sub_dollar_taker_bps : int option
  }
[@@deriving sexp, compare, equal]

let u = Usd.of_string

let bzx_like =
  { name = "bzx-like"
  ; unit = Per_share
  ; maker = u "-0.0016"
  ; taker = u "0.0030"
  ; auction = u "0.0010"
  ; sub_dollar_taker_bps = Some 30
  }
;;

let nyse_like =
  { name = "nyse-like"
  ; unit = Per_share
  ; maker = u "-0.0012"
  ; taker = u "0.00275"
  ; auction = u "0.0010"
  ; sub_dollar_taker_bps = Some 30
  }
;;

let cme_like =
  { name = "cme-like"
  ; unit = Per_contract
  ; maker = u "1"
  ; taker = u "1"
  ; auction = u "1"
  ; sub_dollar_taker_bps = None
  }
;;

let rate t (liquidity : Liquidity.t) =
  match liquidity with
  | Maker -> t.maker
  | Taker -> t.taker
  | Auction -> t.auction
;;

let fee t liquidity ~price ~qty =
  let per_unit () = Usd.of_units (Usd.to_units (rate t liquidity) * qty) in
  match t.unit, t.sub_dollar_taker_bps with
  | Per_share, Some bps when Price.( < ) price Price.one ->
    (match liquidity with
     | Maker -> Usd.zero
     | Taker | Auction -> Usd.of_units (Price.to_units price * qty * bps / 10_000))
  | (Per_share | Per_contract), _ -> per_unit ()
;;

let to_engine t ~price =
  let bps liquidity =
    let fee = Usd.to_units (rate t liquidity) in
    if fee <= 0
    then 0.
    else Float.of_int fee /. Float.of_int (Price.to_units price) *. 10_000.
  in
  { Exchange_core.Fee_schedule.maker_bps = bps Maker; taker_bps = bps Taker }
;;
