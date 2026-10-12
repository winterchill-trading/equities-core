(** Instrument naming: US equity tickers, CME futures contract codes and OCC option
    symbols (OSI). *)

open! Core

module Equity : sig
  (** A ticker root of 1 to 5 upper-case letters plus an optional suffix. Two spellings
      are supported: NYSE symbology separates root and suffix with a space (["BRK B"],
      ["BAC PRL"]); the compact form uses a dot (["BRK.B"], ["BAC.PRL"]). *)

  module Suffix : sig
    type t =
      | Class of char (** share class, ["B"] *)
      | Preferred of char option (** ["PR"], ["PRL"] *)
      | Warrants of char option (** ["WS"], ["WSA"] *)
      | Rights (** ["RT"] *)
      | Units (** ["U"] *)
      | When_issued (** ["WI"] *)
    [@@deriving sexp, compare, equal]

    val of_string : string -> t option
    val to_string : t -> string
  end

  type t = private
    { root : string
    ; suffix : Suffix.t option
    }
  [@@deriving sexp, compare, equal, hash]

  val create : ?suffix:Suffix.t -> string -> t Or_error.t

  (** Parses either spelling. *)
  val of_string : string -> t Or_error.t

  val to_nyse : t -> string
  val to_compact : t -> string

  (** Test symbols commonly configured by US venues for certification (e.g. ["ZVZZT"],
      ["ZXZZT"], ["ZWZZT"] and ["NTEST"]); a simulator should accept orders in them
      outside production hours. *)
  val default_test_symbols : string list

  val is_test : ?test_symbols:string list -> t -> bool
end

module Future : sig
  module Month_code : sig
    (** F Jan, G Feb, H Mar, J Apr, K May, M Jun, N Jul, Q Aug, U Sep, V Oct, X Nov, Z
        Dec. *)
    val of_month : Month.t -> char

    val to_month : char -> Month.t option

    (** The equity index quarterly cycle H, M, U, Z. *)
    val quarterly : Month.t list
  end

  type t =
    { root : string (** e.g. ["ES"] *)
    ; month : Month.t
    ; year : int (** four digits *)
    }
  [@@deriving sexp, compare, equal]

  (** Parses ["ESZ6"] or ["ESZ26"]. A one-digit year is the first year at or after
      [reference_year] ending in that digit; two digits are taken in the 2000s. *)
  val of_string : reference_year:int -> string -> t Or_error.t

  (** Globex style with a one-digit year, e.g. ["ESZ6"]. *)
  val to_string : t -> string

  module Expiry_rule : sig
    type t =
      | Third_friday (** equity index futures: third Friday of the contract month *)
      | Crude_oil
      (** three business days before the 25th of the prior month; four if the 25th is not
          a business day *)
      | Third_last_business_day (** gold *)
    [@@deriving sexp, compare, equal]

    val of_root : string -> t option
  end

  (** Last trading day. Business days are weekdays; exchange holidays are not modelled. *)
  val last_trade_date : t -> Date.t Or_error.t

  val third_friday : year:int -> Month.t -> Date.t

  (** The first contract of [root] in the quarterly cycle whose last trading day is on or
      after [date]. *)
  val front_quarterly : root:string -> Date.t -> t Or_error.t
end

module Osi : sig
  (** OCC option symbology, 21 characters: root padded with spaces to 6, expiry [YYMMDD],
      [C] or [P], strike times 1000 in 8 digits. E.g. ["SPY   261218C00600000"]. *)

  module Right : sig
    type t =
      | Call
      | Put
    [@@deriving sexp, compare, equal, enumerate]
  end

  type t =
    { root : string
    ; expiry : Date.t
    ; right : Right.t
    ; strike : Exchange_core.Price.t
    }
  [@@deriving sexp, compare, equal]

  val of_string : string -> t Or_error.t

  (** Raises if the root is longer than 6 characters or the strike does not fit. *)
  val to_string : t -> string
end
