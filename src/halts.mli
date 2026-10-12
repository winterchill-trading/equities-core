(** Volatility controls for US equities: Limit Up-Limit Down (LULD) price bands with the
    limit state / trading pause state machine, and market-wide circuit breakers.

    LULD percentage parameters, by reference price:
    - Tier 1 (S&P 500, Russell 1000, some ETPs): 5% above $3.00;
    - Tier 2 (other NMS stocks): 10% above $3.00;
    - both tiers: 20% from $0.75 to $3.00, the lesser of $0.15 or 75% below $0.75.

    Bands are doubled from 15:35 to 16:00 ET, except for Tier 2 stocks priced above $3.00.
    Amendment 18 (2020) removed the former doubling from 09:30 to 09:45; it can be
    switched back on with [~double_at_open:true]. Bands are rounded to the nearest penny.
    A stock enters a Limit State when the national best offer equals the lower band or the
    national best bid equals the upper band; if it does not leave it within 15 seconds,
    trading pauses for 5 minutes. *)

open! Core
module Price := Exchange_core.Price

module Tier : sig
  type t =
    | Tier1
    | Tier2
  [@@deriving sexp, compare, equal, enumerate]
end

module Bands : sig
  type t =
    { lower : Price.t
    ; upper : Price.t
    }
  [@@deriving sexp, compare, equal]

  val contains : t -> Price.t -> bool
end

(** The band width as a price amount at a reference price, before doubling. *)
val luld_width : Tier.t -> reference:Price.t -> Price.t

(** Bands at an instant, applying the closing (and optionally opening) doubling. *)
val luld_bands
  :  ?double_at_open:bool
  -> Tier.t
  -> reference:Price.t
  -> at:Time_ns.t
  -> Bands.t

module Luld : sig
  type state =
    | Normal
    | Limit_state of
        { at_upper : bool
        ; since : Time_ns.t
        }
    | Paused of { until : Time_ns.t }
  [@@deriving sexp, compare, equal]

  val limit_state_duration : Time_ns.Span.t
  val pause_duration : Time_ns.Span.t

  type t [@@deriving sexp_of]

  val create : unit -> t
  val state : t -> state

  (** Feeds the national best bid and offer against the current bands. A quote also
      advances time, as {!tick} does. *)
  val on_quote
    :  t
    -> now:Time_ns.t
    -> bands:Bands.t
    -> best_bid:Price.t option
    -> best_offer:Price.t option
    -> unit

  (** Advances time: a limit state older than 15 s becomes a pause, an expired pause
      returns to normal (the listing market then runs a reopening auction). *)
  val tick : t -> now:Time_ns.t -> unit

  (** Whether a trade at [price] may print: not paused and within the bands. *)
  val trade_allowed : t -> bands:Bands.t -> Price.t -> bool
end

module Circuit_breaker : sig
  (** Market-wide circuit breakers on the S&P 500 decline from the prior close: Level 1
      (7%) and Level 2 (13%) halt all trading for 15 minutes if hit before 15:25 ET and
      not at all from 15:25; each can fire once a day. Level 3 (20%) halts trading for the
      rest of the day at any time. *)

  module Level : sig
    type t =
      | Level1
      | Level2
      | Level3
    [@@deriving sexp, compare, equal, enumerate]

    (** Decline in percent: 7, 13, 20. *)
    val percent : t -> int
  end

  type t [@@deriving sexp_of]

  val create : prior_close:Price.t -> t

  (** Feeds an index value; returns the level newly triggered, if any. *)
  val on_index : t -> now:Time_ns.t -> Price.t -> Level.t option

  val is_halted : t -> now:Time_ns.t -> bool
  val triggered : t -> Level.t list
end
