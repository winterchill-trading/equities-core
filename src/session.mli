(** Trading calendars: the US equities trading day (America/New_York) and the CME Globex
    week (America/Chicago).

    Time zones are computed from the US daylight saving rule in force since 2007 (second
    Sunday of March to first Sunday of November, switching at 02:00 local time), so the
    library needs no tz database and gives the same answer on every machine. *)

open! Core

module Zone : sig
  type t =
    | New_york (** UTC-5, UTC-4 in daylight saving time *)
    | Chicago (** UTC-6, UTC-5 in daylight saving time *)
  [@@deriving sexp, compare, equal, enumerate]

  (** Whether daylight saving time is in effect at an instant. *)
  val is_dst : t -> Time_ns.t -> bool

  (** Offset from UTC at an instant, e.g. [-4h] for New York in summer. *)
  val utc_offset : t -> Time_ns.t -> Time_ns.Span.t

  (** Local date and time since local midnight. *)
  val to_local : t -> Time_ns.t -> Date.t * Time_ns.Span.t

  (** Instant of a local date and time. In the spring gap the result is one hour later on
      the wall clock; in the autumn overlap the first (daylight) occurrence is returned. *)
  val of_local : t -> Date.t -> Time_ns.Span.t -> Time_ns.t
end

(** [hm 9 30] is 09:30 as a span since midnight. *)
val hm : int -> int -> Time_ns.Span.t

(** Formats an instant as ["YYYY-MM-DD HH:MM:SS"] local time, for tests and logs. *)
val to_local_string : Zone.t -> Time_ns.t -> string

module Us_equities : sig
  module Phase : sig
    type t =
      | Closed
      | Pre_market (** 04:00 to 09:30 *)
      | Core (** 09:30 to 16:00, 13:00 on early close days *)
      | Post_market (** to 20:00, 17:00 on early close days *)
    [@@deriving sexp, compare, equal, enumerate]
  end

  module Day : sig
    type t =
      | Weekend
      | Holiday of string
      | Early_close of string
      | Regular
    [@@deriving sexp, compare, equal]
  end

  (** Holidays and early closes. Weekdays not listed are regular trading days. *)
  type calendar =
    { holidays : (Date.t * string) list
    ; early_closes : (Date.t * string) list
    }
  [@@deriving sexp]

  (** The NYSE Group calendar for 2026 as published on nyse.com: ten holidays and early
      closes (13:00) on 2026-11-27 and 2026-12-24. *)
  val nyse_2026 : calendar

  (** Calendar years with holiday data in {!nyse_2026}. Other years only know weekends. *)
  val years_covered : calendar -> int list

  val day : ?calendar:calendar -> Date.t -> Day.t
  val is_trading_day : ?calendar:calendar -> Date.t -> bool

  type hours =
    { pre_market_open : Time_ns.Span.t
    ; core_open : Time_ns.Span.t
    ; core_close : Time_ns.Span.t
    ; post_market_close : Time_ns.Span.t
    }
  [@@deriving sexp, compare, equal]

  (** New York local session times of a trading day, [None] on weekends and holidays. *)
  val hours : ?calendar:calendar -> Date.t -> hours option

  val phase_at : ?calendar:calendar -> Time_ns.t -> Phase.t

  (** Instants of the core open and close of a trading day. *)
  val core_open_close : ?calendar:calendar -> Date.t -> (Time_ns.t * Time_ns.t) option

  (** The next trading day strictly after [date]. *)
  val next_trading_day : ?calendar:calendar -> Date.t -> Date.t
end

module Cme_globex : sig
  (** Globex runs from Sunday 17:00 to Friday 16:00 Chicago time with a daily maintenance
      halt from 16:00 to 17:00 Monday to Thursday. Exchange holiday schedules are not
      modelled. *)

  module Phase : sig
    type t =
      | Open
      | Maintenance (** daily 16:00 to 17:00 CT break *)
      | Closed (** Friday 16:00 to Sunday 17:00 CT *)
    [@@deriving sexp, compare, equal, enumerate]
  end

  val phase_at : Time_ns.t -> Phase.t

  (** The trade date a Globex instant belongs to: a session that opens at 17:00 CT counts
      toward the next weekday. [None] when the market is not open. *)
  val trade_date : Time_ns.t -> Date.t option
end
