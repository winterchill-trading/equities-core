(** Minimum price increments.

    - US equities (Reg NMS Rule 612): $0.01 at or above $1.00, $0.0001 below. The 2024
      amendment adding a $0.005 increment for tick-constrained symbols is not modelled.
    - Cboe US options: $0.05 below $3.00 and $0.10 from $3.00; penny program classes $0.01
      below $3.00 and $0.05 from $3.00; some classes (e.g. SPY, QQQ, IWM) $0.01 at every
      price.
    - CME futures: a fixed tick per product, see {!Cme_product}. *)

open! Core
module Price := Exchange_core.Price

(** The equity tick at a price. *)
val equity : Price.t -> Price.t

module Option_class : sig
  type t =
    | Standard
    | Penny (** penny program: $0.01 below $3, $0.05 above *)
    | Penny_all (** $0.01 at every price *)
  [@@deriving sexp, compare, equal, enumerate]
end

(** The option premium tick at a price. *)
val option : Option_class.t -> Price.t -> Price.t

module Cme_product : sig
  type t =
    { root : string (** Globex product code, e.g. ["ES"] *)
    ; name : string
    ; tick : Price.t
    ; multiplier : int (** contract units per price unit *)
    ; unit_of_measure : string (** what [multiplier] counts *)
    }
  [@@deriving sexp, compare, equal]

  (** E-mini S&P 500: 0.25 index points, $50 per point. *)
  val es : t

  (** E-mini Nasdaq-100: 0.25 index points, $20 per point. *)
  val nq : t

  (** WTI crude oil: $0.01 per barrel, 1,000 barrels. *)
  val cl : t

  (** Gold: $0.10 per troy ounce, 100 troy ounces. *)
  val gc : t

  val all : t list
  val find : string -> t option

  (** Dollar value of one tick for one contract, e.g. $12.50 for ES. *)
  val tick_value : t -> Exchange_core.Usd.t

  (** Dollar value of a price move for [contracts] contracts. *)
  val pnl : t -> price_change:Price.t -> contracts:int -> Exchange_core.Usd.t
end

(** Whether a price is a whole multiple of [tick]. *)
val is_on_tick : tick:Price.t -> Price.t -> bool

(** Whether a positive price is valid for an equity order. *)
val is_valid_equity_price : Price.t -> bool

(** Whether a positive price is valid for an option order of a class. *)
val is_valid_option_price : Option_class.t -> Price.t -> bool

(** Rounds to a multiple of [tick]. [`Nearest] rounds halves up. *)
val round : tick:Price.t -> [ `Down | `Up | `Nearest ] -> Price.t -> Price.t
