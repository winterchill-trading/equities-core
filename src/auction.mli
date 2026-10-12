(** Opening, closing and halt auctions (call auctions).

    The clearing price is chosen among the limit prices of the participating orders and
    the reference price by, in order:
    + maximising executed volume;
    + minimising the imbalance (unmatched shares) at that price;
    + being closest to the reference price (usually the last sale or the consolidated
      midpoint, as the venue defines it);
    + if two prices are equally close, the lower.

    Market orders are treated as limit orders at an unbounded price. Allocation follows
    price then time priority (market orders first, then by limit, then by [id]). *)

open! Core
module Price := Exchange_core.Price
module Side := Exchange_core.Side

module Kind : sig
  type t =
    | Opening
    | Closing
    | Halt_reopening
  [@@deriving sexp, compare, equal, enumerate]
end

module Order_kind : sig
  type t =
    | Moo (** market on open *)
    | Loo (** limit on open *)
    | Moc (** market on close *)
    | Loc (** limit on close *)
    | Book (** a limit order resting in the continuous book *)
  [@@deriving sexp, compare, equal, enumerate]

  (** MOO/LOO join only the opening auction, MOC/LOC only the closing auction; resting
      book orders join every auction. *)
  val participates : t -> Kind.t -> bool

  (** Whether the kind carries a limit price (LOO, LOC and book orders). *)
  val has_limit : t -> bool
end

module Order : sig
  type t =
    { id : int (** time priority: lower ids arrived first *)
    ; side : Side.t
    ; qty : int
    ; kind : Order_kind.t
    ; limit : Price.t option (** [None] for MOO and MOC *)
    }
  [@@deriving sexp, compare, equal]

  (** Checks that the limit is present exactly when the kind needs one and the quantity is
      positive. *)
  val validate : t -> unit Or_error.t
end

module Result : sig
  type t =
    { price : Price.t
    ; matched : int
    ; buy_qty : int (** shares willing to buy at [price] *)
    ; sell_qty : int
    ; imbalance : int (** [abs (buy_qty - sell_qty)] *)
    ; imbalance_side : Side.t option
    }
  [@@deriving sexp, compare, equal]
end

(** Clearing price of the orders participating in [kind]. [None] when nothing would
    execute. *)
val clearing : kind:Kind.t -> reference:Price.t -> Order.t list -> Result.t option

(** Order imbalance information, as disseminated before an auction (NYSE Imbalance
    message, Cboe Auction Update). *)
module Imbalance : sig
  type t =
    { kind : Kind.t
    ; reference_price : Price.t
    ; paired_qty : int (** shares matched at the reference price *)
    ; imbalance_qty : int (** unmatched shares at the reference price *)
    ; imbalance_side : Side.t option
    ; market_imbalance_qty : int (** imbalance of market orders alone *)
    ; indicative_price : Price.t option (** the clearing price if run now *)
    ; indicative_matched : int
    }
  [@@deriving sexp, compare, equal]
end

val imbalance : kind:Kind.t -> reference:Price.t -> Order.t list -> Imbalance.t

module Fill : sig
  type t =
    { id : int
    ; side : Side.t
    ; qty : int
    ; price : Price.t
    }
  [@@deriving sexp, compare, equal]
end

(** Runs the auction: the clearing result and one fill per order that trades (possibly
    partially). Orders not listed are not executed and remain (book orders) or are
    cancelled (auction-only orders) as the venue decides. *)
val uncross
  :  kind:Kind.t
  -> reference:Price.t
  -> Order.t list
  -> (Result.t * Fill.t list) option
