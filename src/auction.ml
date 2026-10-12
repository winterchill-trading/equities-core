open! Core
module Price = Exchange_core.Price
module Side = Exchange_core.Side

module Kind = struct
  type t =
    | Opening
    | Closing
    | Halt_reopening
  [@@deriving sexp, compare, equal, enumerate]
end

module Order_kind = struct
  type t =
    | Moo
    | Loo
    | Moc
    | Loc
    | Book
  [@@deriving sexp, compare, equal, enumerate]

  let participates t (kind : Kind.t) =
    match t, kind with
    | (Moo | Loo), Opening -> true
    | (Moc | Loc), Closing -> true
    | Book, _ -> true
    | (Moo | Loo), (Closing | Halt_reopening) | (Moc | Loc), (Opening | Halt_reopening) ->
      false
  ;;

  let has_limit = function
    | Loo | Loc | Book -> true
    | Moo | Moc -> false
  ;;
end

module Order = struct
  type t =
    { id : int
    ; side : Side.t
    ; qty : int
    ; kind : Order_kind.t
    ; limit : Price.t option
    }
  [@@deriving sexp, compare, equal]

  let validate t =
    if t.qty <= 0
    then error_s [%message "auction order quantity must be positive" (t : t)]
    else if Bool.( <> ) (Order_kind.has_limit t.kind) (Option.is_some t.limit)
    then error_s [%message "limit price presence does not match order kind" (t : t)]
    else Ok ()
  ;;

  (* Whether the order is willing to trade at [px]. *)
  let crosses t px =
    match t.limit, t.side with
    | None, _ -> true
    | Some l, Buy -> Price.( >= ) l px
    | Some l, Sell -> Price.( <= ) l px
  ;;
end

module Result = struct
  type t =
    { price : Price.t
    ; matched : int
    ; buy_qty : int
    ; sell_qty : int
    ; imbalance : int
    ; imbalance_side : Side.t option
    }
  [@@deriving sexp, compare, equal]
end

let participating kind orders =
  List.filter orders ~f:(fun (o : Order.t) -> Order_kind.participates o.kind kind)
;;

let at_price orders px =
  let sum side =
    List.sum (module Int) orders ~f:(fun (o : Order.t) ->
      if Side.equal o.side side && Order.crosses o px then o.qty else 0)
  in
  let buy_qty = sum Buy
  and sell_qty = sum Sell in
  { Result.price = px
  ; matched = Int.min buy_qty sell_qty
  ; buy_qty
  ; sell_qty
  ; imbalance = abs (buy_qty - sell_qty)
  ; imbalance_side =
      (if buy_qty > sell_qty
       then Some Buy
       else if sell_qty > buy_qty
       then Some Sell
       else None)
  }
;;

let distance a b = abs (Price.to_units a - Price.to_units b)

let clearing_among ~reference orders =
  let candidates =
    reference :: List.filter_map orders ~f:(fun (o : Order.t) -> o.limit)
    |> List.dedup_and_sort ~compare:Price.compare
  in
  let better (a : Result.t) (b : Result.t) =
    (* [true] if [a] beats [b]. *)
    if a.matched <> b.matched
    then a.matched > b.matched
    else if a.imbalance <> b.imbalance
    then a.imbalance < b.imbalance
    else (
      let da = distance a.price reference
      and db = distance b.price reference in
      if da <> db then da < db else Price.( < ) a.price b.price)
  in
  List.map candidates ~f:(at_price orders)
  |> List.fold ~init:None ~f:(fun best r ->
    match best with
    | Some b when not (better r b) -> best
    | _ -> Some r)
  |> Option.filter ~f:(fun (r : Result.t) -> r.matched > 0)
;;

let clearing ~kind ~reference orders =
  clearing_among ~reference (participating kind orders)
;;

module Imbalance = struct
  type t =
    { kind : Kind.t
    ; reference_price : Price.t
    ; paired_qty : int
    ; imbalance_qty : int
    ; imbalance_side : Side.t option
    ; market_imbalance_qty : int
    ; indicative_price : Price.t option
    ; indicative_matched : int
    }
  [@@deriving sexp, compare, equal]
end

let imbalance ~kind ~reference orders =
  let orders = participating kind orders in
  let at_ref = at_price orders reference in
  let market side =
    List.sum (module Int) orders ~f:(fun (o : Order.t) ->
      if Side.equal o.side side && Option.is_none o.limit then o.qty else 0)
  in
  let indicative = clearing_among ~reference orders in
  { Imbalance.kind
  ; reference_price = reference
  ; paired_qty = at_ref.matched
  ; imbalance_qty = at_ref.imbalance
  ; imbalance_side = at_ref.imbalance_side
  ; market_imbalance_qty = abs (market Buy - market Sell)
  ; indicative_price = Option.map indicative ~f:(fun r -> r.price)
  ; indicative_matched = Option.value_map indicative ~default:0 ~f:(fun r -> r.matched)
  }
;;

module Fill = struct
  type t =
    { id : int
    ; side : Side.t
    ; qty : int
    ; price : Price.t
    }
  [@@deriving sexp, compare, equal]
end

let priority (a : Order.t) (b : Order.t) =
  match a.limit, b.limit with
  | None, None -> Int.compare a.id b.id
  | None, Some _ -> -1
  | Some _, None -> 1
  | Some la, Some lb ->
    let by_price =
      match a.side with
      | Buy -> Price.compare lb la
      | Sell -> Price.compare la lb
    in
    if by_price <> 0 then by_price else Int.compare a.id b.id
;;

let allocate side orders ~price ~matched =
  List.filter orders ~f:(fun (o : Order.t) ->
    Side.equal o.side side && Order.crosses o price)
  |> List.sort ~compare:priority
  |> List.fold_map ~init:matched ~f:(fun left (o : Order.t) ->
    let qty = Int.min left o.qty in
    left - qty, if qty > 0 then Some { Fill.id = o.id; side; qty; price } else None)
  |> snd
  |> List.filter_opt
;;

let uncross ~kind ~reference orders =
  let orders = participating kind orders in
  Option.map (clearing_among ~reference orders) ~f:(fun (r : Result.t) ->
    let fills side = allocate side orders ~price:r.price ~matched:r.matched in
    r, fills Buy @ fills Sell)
;;
