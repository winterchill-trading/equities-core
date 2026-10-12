open! Core

let epoch = Date.create_exn ~y:1970 ~m:Jan ~d:1
let hm h m = Time_ns.Span.of_int_sec ((h * 3600) + (m * 60))

let instant_utc date span =
  Time_ns.add
    (Time_ns.of_int_ns_since_epoch (Date.diff date epoch * 86_400 * 1_000_000_000))
    span
;;

let day_ns = 86_400 * 1_000_000_000

(* Date and time since midnight of an epoch nanosecond count, flooring for negatives. *)
let split_ns ns =
  let days = Int.( / ) ns day_ns - if ns < 0 && ns % day_ns <> 0 then 1 else 0 in
  Date.add_days epoch days, Time_ns.Span.of_int_ns (ns - (days * day_ns))
;;

let nth_weekday ~y ~m ~dow ~n =
  let first = Date.create_exn ~y ~m ~d:1 in
  let delta =
    (Day_of_week.to_int dow - Day_of_week.to_int (Date.day_of_week first) + 7) mod 7
  in
  Date.add_days first (delta + ((n - 1) * 7))
;;

module Zone = struct
  type t =
    | New_york
    | Chicago
  [@@deriving sexp, compare, equal, enumerate]

  let standard_hours = function
    | New_york -> -5
    | Chicago -> -6
  ;;

  (* DST starts at 02:00 local standard time and ends at 02:00 local daylight time. *)
  let is_dst t time =
    let y = Date.year (fst (split_ns (Time_ns.to_int_ns_since_epoch time))) in
    let std = standard_hours t in
    let start =
      instant_utc
        (nth_weekday ~y ~m:Mar ~dow:Sun ~n:2)
        (Time_ns.Span.of_hr (Float.of_int (2 - std)))
    in
    let stop =
      instant_utc
        (nth_weekday ~y ~m:Nov ~dow:Sun ~n:1)
        (Time_ns.Span.of_hr (Float.of_int (2 - (std + 1))))
    in
    Time_ns.( >= ) time start && Time_ns.( < ) time stop
  ;;

  let utc_offset t time =
    let hours = standard_hours t + if is_dst t time then 1 else 0 in
    Time_ns.Span.of_hr (Float.of_int hours)
  ;;

  let to_local t time =
    split_ns
      (Time_ns.to_int_ns_since_epoch time + Time_ns.Span.to_int_ns (utc_offset t time))
  ;;

  let of_local t date span =
    let naive = instant_utc date span in
    let std = Time_ns.Span.of_hr (Float.of_int (standard_hours t)) in
    let dst = Time_ns.Span.( + ) std (Time_ns.Span.of_hr 1.) in
    let as_dst = Time_ns.sub naive dst in
    if is_dst t as_dst then as_dst else Time_ns.sub naive std
  ;;
end

let to_local_string zone time =
  let date, span = Zone.to_local zone time in
  let s = Time_ns.Span.to_int_sec span in
  sprintf "%s %02d:%02d:%02d" (Date.to_string date) (s / 3600) (s / 60 % 60) (s % 60)
;;

let is_weekend date =
  match Date.day_of_week date with
  | Sat | Sun -> true
  | Mon | Tue | Wed | Thu | Fri -> false
;;

module Us_equities = struct
  module Phase = struct
    type t =
      | Closed
      | Pre_market
      | Core
      | Post_market
    [@@deriving sexp, compare, equal, enumerate]
  end

  module Day = struct
    type t =
      | Weekend
      | Holiday of string
      | Early_close of string
      | Regular
    [@@deriving sexp, compare, equal]
  end

  type calendar =
    { holidays : (Date.t * string) list
    ; early_closes : (Date.t * string) list
    }
  [@@deriving sexp]

  let d m day = Date.create_exn ~y:2026 ~m ~d:day

  let nyse_2026 =
    { holidays =
        [ d Jan 1, "New Year's Day"
        ; d Jan 19, "Martin Luther King, Jr. Day"
        ; d Feb 16, "Washington's Birthday"
        ; d Apr 3, "Good Friday"
        ; d May 25, "Memorial Day"
        ; d Jun 19, "Juneteenth National Independence Day"
        ; d Jul 3, "Independence Day (observed)"
        ; d Sep 7, "Labor Day"
        ; d Nov 26, "Thanksgiving Day"
        ; d Dec 25, "Christmas Day"
        ]
    ; early_closes = [ d Nov 27, "Day after Thanksgiving"; d Dec 24, "Christmas Eve" ]
    }
  ;;

  let years_covered calendar =
    List.map (calendar.holidays @ calendar.early_closes) ~f:(fun (date, _) ->
      Date.year date)
    |> List.dedup_and_sort ~compare:Int.compare
  ;;

  let find list date = List.Assoc.find list ~equal:Date.equal date

  let day ?(calendar = nyse_2026) date =
    if is_weekend date
    then Day.Weekend
    else (
      match find calendar.holidays date with
      | Some name -> Holiday name
      | None ->
        (match find calendar.early_closes date with
         | Some name -> Early_close name
         | None -> Regular))
  ;;

  let is_trading_day ?calendar date =
    match day ?calendar date with
    | Weekend | Holiday _ -> false
    | Early_close _ | Regular -> true
  ;;

  type hours =
    { pre_market_open : Time_ns.Span.t
    ; core_open : Time_ns.Span.t
    ; core_close : Time_ns.Span.t
    ; post_market_close : Time_ns.Span.t
    }
  [@@deriving sexp, compare, equal]

  let hours ?calendar date =
    match day ?calendar date with
    | Weekend | Holiday _ -> None
    | Regular ->
      Some
        { pre_market_open = hm 4 0
        ; core_open = hm 9 30
        ; core_close = hm 16 0
        ; post_market_close = hm 20 0
        }
    | Early_close _ ->
      Some
        { pre_market_open = hm 4 0
        ; core_open = hm 9 30
        ; core_close = hm 13 0
        ; post_market_close = hm 17 0
        }
  ;;

  let phase_at ?calendar time =
    let date, span = Zone.to_local New_york time in
    match hours ?calendar date with
    | None -> Phase.Closed
    | Some h ->
      let open Time_ns.Span in
      if span < h.pre_market_open
      then Closed
      else if span < h.core_open
      then Pre_market
      else if span < h.core_close
      then Core
      else if span < h.post_market_close
      then Post_market
      else Closed
  ;;

  let core_open_close ?calendar date =
    Option.map (hours ?calendar date) ~f:(fun h ->
      Zone.of_local New_york date h.core_open, Zone.of_local New_york date h.core_close)
  ;;

  let rec next_trading_day ?calendar date =
    let next = Date.add_days date 1 in
    if is_trading_day ?calendar next then next else next_trading_day ?calendar next
  ;;
end

module Cme_globex = struct
  module Phase = struct
    type t =
      | Open
      | Maintenance
      | Closed
    [@@deriving sexp, compare, equal, enumerate]
  end

  let phase_at time =
    let date, span = Zone.to_local Chicago time in
    let before_16 = Time_ns.Span.( < ) span (hm 16 0) in
    let from_17 = Time_ns.Span.( >= ) span (hm 17 0) in
    match Date.day_of_week date with
    | Sat -> Phase.Closed
    | Sun -> if from_17 then Open else Closed
    | Fri -> if before_16 then Open else Closed
    | Mon | Tue | Wed | Thu -> if before_16 || from_17 then Open else Maintenance
  ;;

  let trade_date time =
    match phase_at time with
    | Maintenance | Closed -> None
    | Open ->
      let date, span = Zone.to_local Chicago time in
      if Time_ns.Span.( >= ) span (hm 17 0)
      then Some (Date.add_days date 1)
      else Some date
  ;;
end
