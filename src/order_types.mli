(** US equities order attributes with validation, and the mapping onto the venue-neutral
    engine's {!Exchange_core.Order_request} where the engine supports the combination. *)

open! Core
module Price := Exchange_core.Price

module Side : sig
  type t =
    | Buy
    | Sell
    | Sell_short
    | Sell_short_exempt (** exempt from the Rule 201 price test *)
  [@@deriving sexp, compare, equal, enumerate]

  val to_core : t -> Exchange_core.Side.t
end

module Tif : sig
  type t =
    | Day
    | Ioc
    | Fok
    | Gtc
    | Opg (** on open: MOO / LOO *)
    | Clo (** on close: MOC / LOC *)
  [@@deriving sexp, compare, equal, enumerate]
end

module Display : sig
  type t =
    | Visible
    | Hidden
    | Reserve of { display_qty : int } (** iceberg: shows [display_qty], refreshes *)
  [@@deriving sexp, compare, equal]
end

module Stp : sig
  (** Self-trade prevention, applied when both sides belong to the same participant. *)
  type t =
    | Allow
    | Cancel_newest
    | Cancel_oldest
    | Cancel_both
    | Decrement_and_cancel (** reduce the larger by the smaller, cancel the smaller *)
  [@@deriving sexp, compare, equal, enumerate]
end

module Ssr : sig
  (** Reg SHO Rule 201 short sale restriction ("alternative uptick rule"). A trade 10% or
      more below the prior close activates it for the rest of that day and the next
      trading day; while active, short sales must be priced above the national best bid.
      Sell short exempt orders are not restricted. *)

  type t [@@deriving sexp, compare, equal]

  val inactive : t

  (** Feeds a trade. [next_trading_day] defaults to the 2026 NYSE calendar. *)
  val on_trade
    :  ?next_trading_day:(Date.t -> Date.t)
    -> t
    -> date:Date.t
    -> prev_close:Price.t
    -> price:Price.t
    -> t

  val is_active : t -> date:Date.t -> bool

  (** Last date on which the restriction applies, if it was ever triggered. *)
  val restricted_through : t -> Date.t option

  val allows
    :  t
    -> date:Date.t
    -> side:Side.t
    -> price:Price.t
    -> national_best_bid:Price.t
    -> bool
end

type t =
  { side : Side.t
  ; qty : int
  ; limit : Price.t option (** [None]: market order *)
  ; tif : Tif.t
  ; display : Display.t
  ; iso : bool (** intermarket sweep order: may trade through away quotes *)
  ; post_only : bool (** add liquidity only *)
  ; min_qty : int option
  ; stp : Stp.t
  }
[@@deriving sexp, compare, equal]

(** A visible day order without ISO, post-only, minimum quantity or STP. *)
val create : ?limit:Price.t -> ?tif:Tif.t -> Side.t -> qty:int -> t

(** Rules checked:
    - quantity positive; limit price positive and on the equity tick;
    - market orders: visible, not post-only, not ISO, not GTC;
    - OPG/CLO orders: visible, not post-only, not ISO, no minimum quantity;
    - IOC/FOK orders: not post-only, not reserve;
    - reserve: display quantity positive, below the order quantity and a multiple of the
      round lot (NYSE requires at least one round lot);
    - minimum quantity between 1 and the order quantity. *)
val validate : ?round_lot:int -> t -> unit Or_error.t

(** Market on open, limit on open, market on close and limit on close constructors. *)
val moo : Side.t -> qty:int -> t

val loo : Side.t -> qty:int -> limit:Price.t -> t
val moc : Side.t -> qty:int -> t
val loc : Side.t -> qty:int -> limit:Price.t -> t

(** The auction order kind of an OPG/CLO order. *)
val auction_kind : t -> Auction.Order_kind.t option

(** Maps to the continuous engine. Day and GTC limits become [Gtc] (the venue cancels day
    orders at the close), post-only becomes [Alo], short sales become sells. FOK, OPG,
    CLO, hidden, reserve and minimum quantity orders are rejected: the engine does not
    implement them. *)
val to_order_request
  :  ?client_order_id:Exchange_core.Client_order_id.t
  -> t
  -> symbol:Exchange_core.Symbol.t
  -> Exchange_core.Order_request.t Or_error.t
