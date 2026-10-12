open! Core
module Price = Exchange_core.Price

module Tier = struct
  type t =
    | Tier1
    | Tier2
  [@@deriving sexp, compare, equal, enumerate]
end

module Bands = struct
  type t =
    { lower : Price.t
    ; upper : Price.t
    }
  [@@deriving sexp, compare, equal]

  let contains t px = Price.( >= ) px t.lower && Price.( <= ) px t.upper
end

let p = Price.of_string
let pct px n = Price.of_units (Price.to_units px * n / 100)

let luld_width (tier : Tier.t) ~reference =
  if Price.( > ) reference (p "3")
  then
    pct
      reference
      (match tier with
       | Tier1 -> 5
       | Tier2 -> 10)
  else if Price.( >= ) reference (p "0.75")
  then pct reference 20
  else Price.min (p "0.15") (pct reference 75)
;;

let in_window ~at ~from ~until =
  let date, span = Session.Zone.to_local New_york at in
  ignore (date : Date.t);
  Time_ns.Span.( >= ) span from && Time_ns.Span.( < ) span until
;;

let luld_bands ?(double_at_open = false) (tier : Tier.t) ~reference ~at =
  let width = luld_width tier ~reference in
  let closing =
    in_window ~at ~from:(Session.hm 15 35) ~until:(Session.hm 16 0)
    &&
    match tier with
    | Tier1 -> true
    | Tier2 -> Price.( <= ) reference (p "3")
  in
  let opening =
    double_at_open && in_window ~at ~from:(Session.hm 9 30) ~until:(Session.hm 9 45)
  in
  let width = if closing || opening then Price.scale width ~by:2 else width in
  let penny x = Price.round_nearest x ~decimals:2 in
  { Bands.lower = penny Price.(reference - width)
  ; upper = penny Price.(reference + width)
  }
;;

module Luld = struct
  type state =
    | Normal
    | Limit_state of
        { at_upper : bool
        ; since : Time_ns.t
        }
    | Paused of { until : Time_ns.t }
  [@@deriving sexp, compare, equal]

  let limit_state_duration = Time_ns.Span.of_int_sec 15
  let pause_duration = Time_ns.Span.of_int_sec 300

  type t = { mutable state : state } [@@deriving sexp_of]

  let create () = { state = Normal }
  let state t = t.state

  let tick t ~now =
    match t.state with
    | Normal -> ()
    | Limit_state { since; _ } ->
      if Time_ns.Span.( >= ) (Time_ns.diff now since) limit_state_duration
      then
        t.state
        <- Paused
             { until =
                 Time_ns.add
                   since
                   (Time_ns.Span.( + ) limit_state_duration pause_duration)
             }
    | Paused { until } -> if Time_ns.( >= ) now until then t.state <- Normal
  ;;

  let on_quote t ~now ~(bands : Bands.t) ~best_bid ~best_offer =
    tick t ~now;
    let at_upper = Option.exists best_bid ~f:(fun b -> Price.( >= ) b bands.upper) in
    let at_lower = Option.exists best_offer ~f:(fun o -> Price.( <= ) o bands.lower) in
    match t.state with
    | Paused _ -> ()
    | Normal ->
      if at_upper || at_lower then t.state <- Limit_state { at_upper; since = now }
    | Limit_state { at_upper = was_upper; _ } ->
      let still = if was_upper then at_upper else at_lower in
      if not still then t.state <- Normal
  ;;

  let trade_allowed t ~bands px =
    match t.state with
    | Paused _ -> false
    | Normal | Limit_state _ -> Bands.contains bands px
  ;;
end

module Circuit_breaker = struct
  module Level = struct
    type t =
      | Level1
      | Level2
      | Level3
    [@@deriving sexp, compare, equal, enumerate]

    let percent = function
      | Level1 -> 7
      | Level2 -> 13
      | Level3 -> 20
    ;;
  end

  type t =
    { prior_close : Price.t
    ; mutable triggered : Level.t list
    ; mutable halted_until : Time_ns.t option
    ; mutable closed_for_day : bool
    }
  [@@deriving sexp_of]

  let create ~prior_close =
    { prior_close; triggered = []; halted_until = None; closed_for_day = false }
  ;;

  let triggered t = List.rev t.triggered

  let is_halted t ~now =
    t.closed_for_day
    || Option.exists t.halted_until ~f:(fun until -> Time_ns.( < ) now until)
  ;;

  let threshold t level = pct t.prior_close (100 - Level.percent level)

  let on_index t ~now value =
    let hit =
      List.rev Level.all
      |> List.find ~f:(fun level -> Price.( <= ) value (threshold t level))
    in
    match hit with
    | None -> None
    | Some level when List.mem t.triggered level ~equal:Level.equal -> None
    | Some level ->
      (* A deeper level also consumes the shallower ones. *)
      List.iter Level.all ~f:(fun l ->
        if Level.compare l level <= 0 && not (List.mem t.triggered l ~equal:Level.equal)
        then t.triggered <- l :: t.triggered);
      (match level with
       | Level3 -> t.closed_for_day <- true
       | Level1 | Level2 ->
         let _, span = Session.Zone.to_local New_york now in
         if Time_ns.Span.( < ) span (Session.hm 15 25)
         then t.halted_until <- Some (Time_ns.add now (Time_ns.Span.of_int_sec 900)));
      Some level
  ;;
end
