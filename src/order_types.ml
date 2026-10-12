open! Core
module Price = Exchange_core.Price

module Side = struct
  type t =
    | Buy
    | Sell
    | Sell_short
    | Sell_short_exempt
  [@@deriving sexp, compare, equal, enumerate]

  let to_core : t -> Exchange_core.Side.t = function
    | Buy -> Buy
    | Sell | Sell_short | Sell_short_exempt -> Sell
  ;;
end

module Tif = struct
  type t =
    | Day
    | Ioc
    | Fok
    | Gtc
    | Opg
    | Clo
  [@@deriving sexp, compare, equal, enumerate]
end

module Display = struct
  type t =
    | Visible
    | Hidden
    | Reserve of { display_qty : int }
  [@@deriving sexp, compare, equal]
end

module Stp = struct
  type t =
    | Allow
    | Cancel_newest
    | Cancel_oldest
    | Cancel_both
    | Decrement_and_cancel
  [@@deriving sexp, compare, equal, enumerate]
end

module Ssr = struct
  type t = { restricted_through : Date.t option } [@@deriving sexp, compare, equal]

  let inactive = { restricted_through = None }
  let restricted_through t = t.restricted_through

  let is_active t ~date =
    match t.restricted_through with
    | None -> false
    | Some last -> Date.( <= ) date last
  ;;

  let on_trade
    ?(next_trading_day = fun d -> Session.Us_equities.next_trading_day d)
    t
    ~date
    ~prev_close
    ~price
    =
    (* Triggered at a decline of 10% or more: price <= 0.9 * prev_close. *)
    if 10 * Price.to_units price <= 9 * Price.to_units prev_close
       && not (is_active t ~date:(next_trading_day date))
    then { restricted_through = Some (next_trading_day date) }
    else t
  ;;

  let allows t ~date ~(side : Side.t) ~price ~national_best_bid =
    match side with
    | Buy | Sell | Sell_short_exempt -> true
    | Sell_short -> (not (is_active t ~date)) || Price.( > ) price national_best_bid
  ;;
end

type t =
  { side : Side.t
  ; qty : int
  ; limit : Price.t option
  ; tif : Tif.t
  ; display : Display.t
  ; iso : bool
  ; post_only : bool
  ; min_qty : int option
  ; stp : Stp.t
  }
[@@deriving sexp, compare, equal]

let create ?limit ?(tif = Tif.Day) side ~qty =
  { side
  ; qty
  ; limit
  ; tif
  ; display = Visible
  ; iso = false
  ; post_only = false
  ; min_qty = None
  ; stp = Allow
  }
;;

let moo side ~qty = create side ~qty ~tif:Opg
let loo side ~qty ~limit = create side ~qty ~limit ~tif:Opg
let moc side ~qty = create side ~qty ~tif:Clo
let loc side ~qty ~limit = create side ~qty ~limit ~tif:Clo

let auction_kind t : Auction.Order_kind.t option =
  match t.tif, t.limit with
  | Opg, None -> Some Moo
  | Opg, Some _ -> Some Loo
  | Clo, None -> Some Moc
  | Clo, Some _ -> Some Loc
  | (Day | Ioc | Fok | Gtc), _ -> None
;;

let validate ?(round_lot = Lot.default_round_lot) t =
  let errors =
    List.filter_map
      ~f:(fun (bad, msg) -> Option.some_if bad msg)
      [ t.qty <= 0, "quantity must be positive"
      ; ( (match t.limit with
           | None -> false
           | Some px -> not (Tick_size.is_valid_equity_price px))
        , "limit price must be positive and on the tick" )
      ; ( Option.is_none t.limit
          && (t.post_only
              || t.iso
              || (not (Display.equal t.display Visible))
              || Tif.equal t.tif Gtc)
        , "market orders must be visible, not post-only, not ISO and not GTC" )
      ; ( (match t.tif with
           | Opg | Clo ->
             t.post_only
             || t.iso
             || Option.is_some t.min_qty
             || not (Display.equal t.display Visible)
           | Day | Ioc | Fok | Gtc -> false)
        , "auction orders must be visible without post-only, ISO or minimum quantity" )
      ; ( (match t.tif, t.display with
           | (Ioc | Fok), Reserve _ -> true
           | (Ioc | Fok), (Visible | Hidden) -> t.post_only
           | (Day | Gtc | Opg | Clo), _ -> false)
        , "IOC and FOK orders cannot be post-only or reserve" )
      ; ( (match t.display with
           | Reserve { display_qty } ->
             display_qty <= 0 || display_qty >= t.qty || display_qty % round_lot <> 0
           | Visible | Hidden -> false)
        , "reserve display quantity must be a round lot multiple below the order quantity"
        )
      ; ( (match t.min_qty with
           | None -> false
           | Some m -> m <= 0 || m > t.qty)
        , "minimum quantity must be between 1 and the order quantity" )
      ]
  in
  match errors with
  | [] -> Ok ()
  | _ -> error_s [%message "invalid order" ~_:(errors : string list) (t : t)]
;;

let to_order_request ?client_order_id t ~symbol =
  let open Or_error.Let_syntax in
  let%bind () = validate t in
  let side = Side.to_core t.side in
  let size = Exchange_core.Size.of_int t.qty in
  let unsupported what = error_s [%message "not supported by the engine" what (t : t)] in
  match t.display, t.min_qty, t.tif, t.limit with
  | (Hidden | Reserve _), _, _, _ -> unsupported "hidden or reserve display"
  | _, Some _, _, _ -> unsupported "minimum quantity"
  | _, _, (Fok | Opg | Clo), _ -> unsupported "time in force"
  | Visible, None, (Day | Ioc), None ->
    Ok (Exchange_core.Order_request.market ?client_order_id symbol side ~size)
  | Visible, None, Gtc, None -> unsupported "GTC market order"
  | Visible, None, ((Day | Gtc | Ioc) as tif), Some px ->
    let tif : Exchange_core.Tif.t =
      match tif with
      | Ioc -> Ioc
      | Day | Gtc | Fok | Opg | Clo -> if t.post_only then Alo else Gtc
    in
    Ok (Exchange_core.Order_request.limit ?client_order_id ~tif symbol side ~px ~size)
;;
