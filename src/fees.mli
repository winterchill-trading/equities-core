(** Maker/taker fee schedules charged per share (equities) or per contract (futures).

    Rates are signed: positive is a fee, negative a rebate. The presets are illustrative
    shapes of the venues' published schedules (a maker-taker equities venue, an NYSE-style
    venue with an auction fee, a flat per-contract futures venue), not current prices; a
    simulator wanting real economics should build its own {!t}. *)

open! Core
module Price := Exchange_core.Price
module Usd := Exchange_core.Usd

module Liquidity : sig
  type t =
    | Maker (** added liquidity *)
    | Taker (** removed liquidity *)
    | Auction (** executed in an opening, closing or halt auction *)
  [@@deriving sexp, compare, equal, enumerate]
end

module Unit : sig
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
  (** shares priced below $1: takers pay this many basis points of notional instead (Rule
      610 caps access fees at 0.3% there), makers get no rebate *)
  }
[@@deriving sexp, compare, equal]

(** Maker rebate $0.0016, taker fee $0.0030, auction $0.0010 per share; 30 bp of notional
    to take below $1. *)
val bzx_like : t

(** Maker rebate $0.0012, taker fee $0.00275, auction $0.0010 per share; 30 bp below $1. *)
val nyse_like : t

(** $1.00 per contract per side whatever the liquidity; no rebates. *)
val cme_like : t

(** Fee for one execution; negative values are rebates paid to the member. *)
val fee : t -> Liquidity.t -> price:Price.t -> qty:int -> Usd.t

(** Converts to the engine's basis point schedule at a representative price, for adapters
    that run {!Exchange_core} with its notional fees. Rebates become zero: the engine does
    not pay rebates. *)
val to_engine : t -> price:Price.t -> Exchange_core.Fee_schedule.t
