open! Core
module Price = Exchange_core.Price

let is_upper c = Char.( >= ) c 'A' && Char.( <= ) c 'Z'

module Equity = struct
  module Suffix = struct
    type t =
      | Class of char
      | Preferred of char option
      | Warrants of char option
      | Rights
      | Units
      | When_issued
    [@@deriving sexp, compare, equal, hash]

    let series prefix s =
      match String.chop_prefix s ~prefix with
      | Some "" -> Some None
      | Some rest when String.length rest = 1 && is_upper rest.[0] -> Some (Some rest.[0])
      | Some _ | None -> None
    ;;

    let of_string s =
      match s with
      | "RT" -> Some Rights
      | "U" -> Some Units
      | "WI" -> Some When_issued
      | _ when String.length s = 1 && is_upper s.[0] -> Some (Class s.[0])
      | _ ->
        (match series "PR" s with
         | Some c -> Some (Preferred c)
         | None -> Option.map (series "WS" s) ~f:(fun c -> Warrants c))
    ;;

    let opt = function
      | None -> ""
      | Some c -> String.of_char c
    ;;

    let to_string = function
      | Class c -> String.of_char c
      | Preferred c -> "PR" ^ opt c
      | Warrants c -> "WS" ^ opt c
      | Rights -> "RT"
      | Units -> "U"
      | When_issued -> "WI"
    ;;
  end

  type t =
    { root : string
    ; suffix : Suffix.t option
    }
  [@@deriving sexp, compare, equal, hash]

  let create ?suffix root =
    let len = String.length root in
    if len >= 1 && len <= 5 && String.for_all root ~f:is_upper
    then Ok { root; suffix }
    else error_s [%message "invalid ticker root" root]
  ;;

  let of_string s =
    match String.lsplit2 s ~on:(if String.mem s ' ' then ' ' else '.') with
    | None -> create s
    | Some (root, suffix) ->
      (match Suffix.of_string suffix with
       | Some suffix -> create ~suffix root
       | None -> error_s [%message "invalid ticker suffix" s])
  ;;

  let render sep t =
    match t.suffix with
    | None -> t.root
    | Some s -> t.root ^ sep ^ Suffix.to_string s
  ;;

  let to_nyse = render " "
  let to_compact = render "."
  let default_test_symbols = [ "ZVZZT"; "ZWZZT"; "ZXZZT"; "NTEST" ]

  let is_test ?(test_symbols = default_test_symbols) t =
    Option.is_none t.suffix && List.mem test_symbols t.root ~equal:String.equal
  ;;
end

module Future = struct
  module Month_code = struct
    let codes = "FGHJKMNQUVXZ"
    let of_month m = codes.[Month.to_int m - 1]

    let to_month c =
      Option.map (String.index codes c) ~f:(fun i -> Month.of_int_exn (i + 1))
    ;;

    let quarterly = [ Month.Mar; Jun; Sep; Dec ]
  end

  type t =
    { root : string
    ; month : Month.t
    ; year : int
    }
  [@@deriving sexp, compare, equal]

  let of_string ~reference_year s =
    let digits = String.length s - String.length (String.rstrip s ~drop:Char.is_digit) in
    let n = String.length s in
    if digits < 1 || digits > 2 || n < digits + 2
    then error_s [%message "invalid futures code" s]
    else (
      let root = String.prefix s (n - digits - 1) in
      let code = s.[n - digits - 1] in
      let y = Int.of_string (String.suffix s digits) in
      match Month_code.to_month code with
      | None -> error_s [%message "invalid futures month code" s]
      | Some month ->
        if not (String.for_all root ~f:(fun c -> is_upper c || Char.is_digit c))
        then error_s [%message "invalid futures root" s]
        else (
          let year =
            if digits = 2
            then 2000 + y
            else (
              let base = reference_year - (reference_year % 10) + y in
              if base < reference_year then base + 10 else base)
          in
          Ok { root; month; year }))
  ;;

  let to_string t = sprintf "%s%c%d" t.root (Month_code.of_month t.month) (t.year % 10)

  module Expiry_rule = struct
    type t =
      | Third_friday
      | Crude_oil
      | Third_last_business_day
    [@@deriving sexp, compare, equal]

    let of_root = function
      | "ES" | "NQ" | "MES" | "MNQ" | "RTY" | "YM" -> Some Third_friday
      | "CL" -> Some Crude_oil
      | "GC" -> Some Third_last_business_day
      | _ -> None
    ;;
  end

  let is_business_day d =
    match Date.day_of_week d with
    | Sat | Sun -> false
    | Mon | Tue | Wed | Thu | Fri -> true
  ;;

  let rec back_business_days d n =
    if n = 0
    then d
    else (
      let prev = Date.add_days d (-1) in
      if is_business_day prev
      then back_business_days prev (n - 1)
      else back_business_days prev n)
  ;;

  let third_friday ~year month =
    let first = Date.create_exn ~y:year ~m:month ~d:1 in
    let to_friday =
      (Day_of_week.to_int Fri - Day_of_week.to_int (Date.day_of_week first) + 7) mod 7
    in
    Date.add_days first (to_friday + 14)
  ;;

  let last_trade_date t =
    match Expiry_rule.of_root t.root with
    | None -> error_s [%message "no expiry rule for root" t.root]
    | Some Third_friday -> Ok (third_friday ~year:t.year t.month)
    | Some Crude_oil ->
      let prior = Date.add_months (Date.create_exn ~y:t.year ~m:t.month ~d:25) (-1) in
      Ok (back_business_days prior (if is_business_day prior then 3 else 4))
    | Some Third_last_business_day ->
      let next_first = Date.add_months (Date.create_exn ~y:t.year ~m:t.month ~d:1) 1 in
      Ok (back_business_days next_first 3)
  ;;

  let front_quarterly ~root date =
    let rec go year = function
      | [] -> go (year + 1) Month_code.quarterly
      | month :: rest ->
        let t = { root; month; year } in
        (match last_trade_date t with
         | Error _ as e -> e
         | Ok last -> if Date.( >= ) last date then Ok t else go year rest)
    in
    go (Date.year date) Month_code.quarterly
  ;;
end

module Osi = struct
  module Right = struct
    type t =
      | Call
      | Put
    [@@deriving sexp, compare, equal, enumerate]
  end

  type t =
    { root : string
    ; expiry : Date.t
    ; right : Right.t
    ; strike : Price.t
    }
  [@@deriving sexp, compare, equal]

  (* Strikes are quoted in thousandths; Price counts 10^-8. *)
  let units_per_milli = Price.units_per_one / 1000

  let of_string s =
    let open Or_error.Let_syntax in
    if String.length s <> 21
    then error_s [%message "OSI symbol must be 21 characters" s]
    else (
      let root = String.rstrip (String.prefix s 6) in
      let date = String.sub s ~pos:6 ~len:6 in
      let strike = String.sub s ~pos:13 ~len:8 in
      let%bind () =
        if String.is_empty root
           || not (String.for_all root ~f:(fun c -> is_upper c || Char.is_digit c))
        then error_s [%message "invalid OSI root" s]
        else Ok ()
      in
      let%bind right =
        match s.[12] with
        | 'C' -> Ok Right.Call
        | 'P' -> Ok Put
        | _ -> error_s [%message "invalid OSI right" s]
      in
      let%bind () =
        if String.for_all (date ^ strike) ~f:Char.is_digit
        then Ok ()
        else error_s [%message "invalid OSI digits" s]
      in
      let%map expiry =
        Or_error.try_with (fun () ->
          Date.create_exn
            ~y:(2000 + Int.of_string (String.sub date ~pos:0 ~len:2))
            ~m:(Month.of_int_exn (Int.of_string (String.sub date ~pos:2 ~len:2)))
            ~d:(Int.of_string (String.sub date ~pos:4 ~len:2)))
      in
      { root
      ; expiry
      ; right
      ; strike = Price.of_units (Int.of_string strike * units_per_milli)
      })
  ;;

  let to_string t =
    let units = Price.to_units t.strike in
    if String.length t.root > 6 || String.is_empty t.root
    then raise_s [%message "OSI root must be 1 to 6 characters" t.root];
    if units < 0 || units % units_per_milli <> 0 || units / units_per_milli > 99_999_999
    then raise_s [%message "OSI strike out of range" (t.strike : Price.t)];
    sprintf
      "%-6s%02d%02d%02d%c%08d"
      t.root
      (Date.year t.expiry % 100)
      (Month.to_int (Date.month t.expiry))
      (Date.day t.expiry)
      (match t.right with
       | Call -> 'C'
       | Put -> 'P')
      (units / units_per_milli)
  ;;
end
