open! Core
open! Async
open Grid_types

type t =
  { config : Config.t
  ; transport : Transport.t
  ; policy : Transport.Retry.policy
  ; log : Sexp.t -> unit
  ; mutable sandbox_checked : bool
  }

let create
  ?(transport = Transport.cohttp ())
  ?(policy = Transport.Retry.default)
  ?(log = fun sexp -> Log.Global.debug_s sexp)
  config
  =
  { config; transport; policy; log; sandbox_checked = false }
;;

let decode_response ?(redact = Fn.id) ~what of_json (response : Transport.Response.t) =
  let request_id = Transport.Response.request_id response in
  if response.status = 429
  then
    Error
      (Api_error.Rate_limited
         { retry_after = Transport.Response.retry_after response; request_id })
  else if response.status < 200 || response.status >= 300
  then (
    let code, reason =
      match Error_body.t_of_yojson (Yojson.Safe.from_string response.body) with
      | { code; reason } -> Some code, reason
      | exception _ -> None, None
    in
    Error
      (Api_error.Http
         { status = response.status
         ; code
         ; reason = Option.map reason ~f:redact
         ; request_id
         ; body = redact response.body
         }))
  else (
    match of_json (Yojson.Safe.from_string response.body) with
    | x -> Ok x
    | exception exn ->
      Error
        (Api_error.Decode
           { what; message = String.prefix (redact (Exn.to_string exn)) 500 }))
;;

let uri t path query =
  let base = t.config.grid_url in
  let base_path = String.chop_suffix_if_exists (Uri.path base) ~suffix:"/" in
  Uri.with_query' (Uri.with_path base (base_path ^ path)) (List.filter_opt query)
;;

let request ?body ?idempotency_key ?(query = []) t ~meth ~path ~what of_json =
  let idempotent =
    match meth with
    | `GET | `DELETE | `PUT -> true
    | `POST | `PATCH -> Option.is_some idempotency_key
  in
  let headers =
    [ Auth.header t.config; "Accept", "application/json" ]
    @ Option.value_map body ~default:[] ~f:(fun _ ->
      [ "Content-Type", "application/json" ])
    @ Option.value_map idempotency_key ~default:[] ~f:(fun k -> [ "Idempotency-Key", k ])
  in
  let request =
    { Transport.Request.meth
    ; uri = uri t path query
    ; headers
    ; body = Option.map body ~f:Yojson.Safe.to_string
    ; idempotent
    }
  in
  match%map Transport.Retry.run ~policy:t.policy ~log:t.log t.transport request with
  | Error message -> Error (Api_error.Transport (Auth.redact t.config message))
  | Ok response ->
    t.log
      [%message
        "lightspark grid"
          ~meth:(meth : Transport.Meth.t)
          (path : string)
          ~status:(response.status : int)
          ~request_id:
            (Option.value (Transport.Response.request_id response) ~default:"-" : string)];
    decode_response ~redact:(Auth.redact t.config) ~what of_json response
;;

let get ?query t ~path ~what of_json = request ?query t ~meth:`GET ~path ~what of_json
let q name f = Option.map ~f:(fun v -> name, f v)

let page_query ?limit ?cursor () =
  [ q "limit" Int.to_string limit; q "cursor" Fn.id cursor ]
;;

let platform_config t = get t ~path:"/config" ~what:"config" Platform_config.t_of_yojson

let customers ?limit ?cursor ?platform_customer_id t =
  get
    t
    ~path:"/customers"
    ~query:
      (page_query ?limit ?cursor ()
       @ [ q "platformCustomerId" Fn.id platform_customer_id ])
    ~what:"customers"
    (Page.of_json Customer.t_of_yojson)
;;

let path_id id = Uri.pct_encode ~component:`Path id

let customer t ~id =
  get t ~path:("/customers/" ^ path_id id) ~what:"customer" Customer.t_of_yojson
;;

let customer_internal_accounts ?limit ?cursor ?customer_id ?currency t =
  get
    t
    ~path:"/customers/internal-accounts"
    ~query:
      (page_query ?limit ?cursor ()
       @ [ q "customerId" Fn.id customer_id; q "currency" Fn.id currency ])
    ~what:"internal accounts"
    (Page.of_json Internal_account.t_of_yojson)
;;

let platform_internal_accounts t =
  get
    t
    ~path:"/platform/internal-accounts"
    ~what:"platform internal accounts"
    (Page.of_json Internal_account.t_of_yojson)
;;

let internal_account t ~id =
  get
    t
    ~path:("/internal-accounts/" ^ path_id id)
    ~what:"internal account"
    Internal_account.t_of_yojson
;;

let transactions ?limit ?cursor ?customer_id ?status ?type_ t =
  get
    t
    ~path:"/transactions"
    ~query:
      (page_query ?limit ?cursor ()
       @ [ q "customerId" Fn.id customer_id
         ; q "status" Fn.id status
         ; q "type" Fn.id type_
         ])
    ~what:"transactions"
    (Page.of_json Transaction.t_of_yojson)
;;

let transaction t ~id =
  get t ~path:("/transactions/" ^ path_id id) ~what:"transaction" Transaction.t_of_yojson
;;

let exchange_rates ?source_currency ?destination_currency ?sending_amount t =
  get
    t
    ~path:"/exchange-rates"
    ~query:
      [ q "sourceCurrency" Fn.id source_currency
      ; q "destinationCurrency" Fn.id destination_currency
      ; q "sendingAmount" Int.to_string sending_amount
      ]
    ~what:"exchange rates"
    (fun json ->
      List.map
        (Yojson.Safe.Util.to_list (Yojson.Safe.Util.member "data" json))
        ~f:Exchange_rate.t_of_yojson)
;;

let quote t ~id = get t ~path:("/quotes/" ^ path_id id) ~what:"quote" Quote.t_of_yojson

let all_pages ?(max_pages = 100) fetch =
  let rec loop acc cursor n =
    match%bind fetch ~cursor with
    | Error _ as e -> return e
    | Ok (page : _ Page.t) ->
      let acc = List.rev_append page.data acc in
      (match page.has_more, page.next_cursor with
       | true, Some next when n < max_pages -> loop acc (Some next) (n + 1)
       | _ -> return (Ok (List.rev acc)))
  in
  loop [] None 1
;;

let ensure_sandbox_or_live t =
  if Config.is_live t.config || t.sandbox_checked
  then return (Ok ())
  else (
    match%map platform_config t with
    | Error _ as e -> e
    | Ok config when Platform_config.looks_like_sandbox config ->
      t.sandbox_checked <- true;
      Ok ()
    | Ok _ ->
      Error
        (Api_error.Refused
           "platform does not look like a Grid sandbox; build the config with ~live:true \
            to allow writes"))
;;

let guarded t f =
  match%bind ensure_sandbox_or_live t with
  | Error _ as e -> return e
  | Ok () -> f ()
;;

let create_individual_customer
  ?region
  ?currencies
  ?email
  t
  ~platform_customer_id
  ~full_name
  ~birth_date
  ~nationality
  ~idempotency_key
  =
  let body =
    `Assoc
      (List.filter_opt
         [ Some ("customerType", `String "INDIVIDUAL")
         ; Some ("platformCustomerId", `String platform_customer_id)
         ; Some ("fullName", `String full_name)
         ; Some ("birthDate", `String birth_date)
         ; Some ("nationality", `String nationality)
         ; q "region" (fun r -> `String r) region
         ; q "currencies" (fun l -> `List (List.map l ~f:(fun c -> `String c))) currencies
         ; q "email" (fun e -> `String e) email
         ])
  in
  guarded t (fun () ->
    request
      t
      ~meth:`POST
      ~path:"/customers"
      ~body
      ~idempotency_key
      ~what:"create customer"
      Customer.t_of_yojson)
;;

let sandbox_fund_internal_account ?description t ~account_id ~amount =
  let body =
    `Assoc
      (List.filter_opt
         [ Some ("amount", `Int amount)
         ; q "description" (fun d -> `String d) description
         ])
  in
  request
    t
    ~meth:`POST
    ~path:("/sandbox/internal-accounts/" ^ path_id account_id ^ "/fund")
    ~body
    ~what:"sandbox fund"
    Internal_account.t_of_yojson
;;

module Destination = struct
  type t =
    | Account of string
    | Uma_address of
        { address : string
        ; currency : string
        }

  let to_json = function
    | Account id ->
      `Assoc [ "destinationType", `String "ACCOUNT"; "accountId", `String id ]
    | Uma_address { address; currency } ->
      `Assoc
        [ "destinationType", `String "UMA_ADDRESS"
        ; "umaAddress", `String address
        ; "currency", `String currency
        ]
  ;;
end

let create_quote
  ?immediately_execute
  ?description
  ?sender_customer_info
  t
  ~source_account_id
  ~destination
  ~locked_side
  ~amount
  ~idempotency_key
  =
  let body =
    `Assoc
      (List.filter_opt
         [ Some
             ( "source"
             , `Assoc
                 [ "sourceType", `String "ACCOUNT"
                 ; "accountId", `String source_account_id
                 ] )
         ; Some ("destination", Destination.to_json destination)
         ; Some
             ( "lockedCurrencySide"
             , `String
                 (match locked_side with
                  | `Sending -> "SENDING"
                  | `Receiving -> "RECEIVING") )
         ; Some ("lockedCurrencyAmount", `Int amount)
         ; q "immediatelyExecute" (fun b -> `Bool b) immediately_execute
         ; q "description" (fun d -> `String d) description
         ; q
             "senderCustomerInfo"
             (fun l -> `Assoc (List.map l ~f:(fun (k, v) -> k, `String v)))
             sender_customer_info
         ])
  in
  guarded t (fun () ->
    request
      t
      ~meth:`POST
      ~path:"/quotes"
      ~body
      ~idempotency_key
      ~what:"create quote"
      Quote.t_of_yojson)
;;

let execute_quote t ~quote_id ~idempotency_key =
  guarded t (fun () ->
    request
      t
      ~meth:`POST
      ~path:("/quotes/" ^ path_id quote_id ^ "/execute")
      ~idempotency_key
      ~what:"execute quote"
      Quote.t_of_yojson)
;;
