(** Order sizes: equity round, odd and mixed lots, and CME contract units.

    The classic US equities round lot is 100 shares. Since the SEC market data
    infrastructure rules, the round lot also depends on the stock's price (average closing
    price over the prior month): 100 shares up to $250, 40 up to $1,000, 10 up to $10,000
    and 1 above. {!round_lot_for_price} gives that tier; everything else takes the round
    lot as a parameter defaulting to 100. *)

open! Core

val default_round_lot : int

(** Round lot under the price tiers above. *)
val round_lot_for_price : Exchange_core.Price.t -> int

module Kind : sig
  type t =
    | Round (** a positive multiple of the round lot *)
    | Odd (** fewer shares than one round lot *)
    | Mixed (** more than one round lot but not a multiple *)
  [@@deriving sexp, compare, equal, enumerate]
end

(** Classifies a positive share quantity. Raises on zero or negative quantities. *)
val classify : ?round_lot:int -> int -> Kind.t

(** [split q] is [(round_part, odd_part)] with [round_part] a multiple of the round lot. *)
val split : ?round_lot:int -> int -> int * int

(** Number of whole round lots, as displayed on some quote feeds. *)
val round_lots : ?round_lot:int -> int -> int

module Contract : sig
  (** CME futures trade in whole contracts; one contract is [multiplier] units of
      {!Tick_size.Cme_product.unit_of_measure}. *)

  (** Human-readable contract unit, e.g. ["1000 barrels"]. *)
  val unit_description : Tick_size.Cme_product.t -> string

  (** Notional value of [contracts] at [price]. *)
  val notional
    :  Tick_size.Cme_product.t
    -> price:Exchange_core.Price.t
    -> contracts:int
    -> Exchange_core.Usd.t

  (** Order quantities must be positive whole contracts up to [max]. *)
  val validate_quantity : ?max:int -> int -> unit Or_error.t
end
