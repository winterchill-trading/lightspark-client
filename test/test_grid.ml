open! Core
open! Async
open Lightspark_client
module G = Grid_types

let decode what f path =
  Grid.decode_response ~what f (Fixture.response path) |> Api_error.ok_exn
;;

let%expect_test "platform config" =
  let c = decode "config" G.Platform_config.t_of_yojson "grid/config.json" in
  print_s
    [%sexp
      (G.Platform_config.looks_like_sandbox c : bool)
      , (List.map c.supported_currencies ~f:(fun s -> s.currency_code) : string list)];
  [%expect {| (true (USD USDB USDC USDT)) |}];
  return ()
;;

let%expect_test "customers page" =
  let page =
    decode "customers" (G.Page.of_json G.Customer.t_of_yojson) "grid/customers.json"
  in
  print_s
    [%sexp
      { has_more : bool = page.has_more
      ; next_cursor : string option = page.next_cursor
      ; total_count : int option = page.total_count
      ; first : G.Customer.t = List.hd_exn page.data
      }];
  [%expect
    {|
    ((has_more true) (next_cursor (cursor-example)) (total_count (12))
     (first
      ((id Customer:00000000-0000-0000-0000-000000000001)
       (platform_customer_id (customer-1)) (customer_type INDIVIDUAL)
       (uma_address ($test.user@examplesandbox.umaaas.uma.money))
       (kyc_status (APPROVED)) (full_name ("Test User"))
       (email (user@example.com)) (is_deleted (false))
       (created_at 2026-10-13T19:57:40.701496Z)
       (updated_at 2026-10-13T19:57:40.762117Z))))
    |}];
  return ()
;;

let%expect_test "internal accounts and balances" =
  List.iter
    [ "grid/internal_accounts.json"; "grid/platform_internal_accounts.json" ]
    ~f:(fun path ->
      let page = decode "accounts" (G.Page.of_json G.Internal_account.t_of_yojson) path in
      List.iter page.data ~f:(fun (a : G.Internal_account.t) ->
        printf "%s %s %s\n" a.type_ a.status (G.Amount.to_string_hum a.balance)));
  [%expect
    {|
    INTERNAL_CRYPTO ACTIVE 0.000000 USDT
    INTERNAL_CRYPTO ACTIVE 5.000000 USDC
    INTERNAL_FIAT ACTIVE 1600.00 USD
    INTERNAL_CRYPTO ACTIVE 0.000000 USDC
    |}];
  return ()
;;

let%expect_test "transactions" =
  List.iter
    [ "grid/transactions_page1.json"; "grid/transactions_page3.json" ]
    ~f:(fun path ->
      let page = decode "transactions" (G.Page.of_json G.Transaction.t_of_yojson) path in
      printf "has_more=%b\n" page.has_more;
      List.iter page.data ~f:(fun (t : G.Transaction.t) ->
        printf
          "  %s %s %s\n"
          t.type_
          t.status
          (Option.value_map t.received_amount ~default:"-" ~f:G.Amount.to_string_hum)));
  let t = decode "transaction" G.Transaction.t_of_yojson "grid/transaction.json" in
  print_s [%sexp (t : G.Transaction.t)];
  [%expect
    {|
    has_more=true
      INCOMING COMPLETED 5.000000 USDC
      INCOMING COMPLETED 10.00 USD
    has_more=true
      INCOMING COMPLETED 10.00 USD
      INCOMING COMPLETED 10.00 USD
    ((id Transaction:00000000-0000-0000-0000-000000000001) (type_ INCOMING)
     (status PROCESSING) (direction (CREDIT))
     (customer_id (Customer:00000000-0000-0000-0000-000000000001))
     (platform_customer_id (customer-1)) (description ())
     (sent_amount
      (((amount 500)
        (currency ((code USD) (decimals 2) (name ("US Dollar")) (symbol ($)))))))
     (received_amount
      (((amount 5000000)
        (currency ((code USDC) (decimals 6) (name ("USD Coin")) (symbol (usdc)))))))
     (quote_id (Quote:00000000-0000-0000-0000-000000000001)) (failure_reason ())
     (created_at 2026-10-13T20:03:30.410737Z)
     (updated_at (2026-10-13T20:03:31.125837Z)) (settled_at ()))
    |}];
  return ()
;;

let%expect_test "rates, quotes and sandbox funding" =
  let rates =
    decode
      "rates"
      (fun json ->
        List.map
          (Yojson.Safe.Util.to_list (Yojson.Safe.Util.member "data" json))
          ~f:G.Exchange_rate.t_of_yojson)
      "grid/exchange_rates.json"
  in
  List.iter rates ~f:(fun (r : G.Exchange_rate.t) ->
    printf
      "%s->%s via %s\n"
      r.source_currency.code
      r.destination_currency.code
      (Option.value r.destination_payment_rail ~default:"-"));
  List.iter [ "grid/create_quote.json"; "grid/execute_quote.json" ] ~f:(fun path ->
    let q = decode "quote" G.Quote.t_of_yojson path in
    printf
      "%s %s sends %d %s receives %d %s\n"
      q.id
      q.status
      q.total_sending_amount
      q.sending_currency.code
      q.total_receiving_amount
      q.receiving_currency.code);
  let funded = decode "fund" G.Internal_account.t_of_yojson "grid/sandbox_fund.json" in
  print_endline (G.Amount.to_string_hum funded.balance);
  let customer = decode "customer" G.Customer.t_of_yojson "grid/create_customer.json" in
  print_s [%sexp (customer.kyc_status : string option)];
  [%expect
    {|
    USD->BRL via PIX
    USD->INR via UPI
    USD->GBP via FASTER_PAYMENTS
    Quote:00000000-0000-0000-0000-000000000001 PENDING sends 500 USD receives 5000000 USDC
    Quote:00000000-0000-0000-0000-000000000001 PROCESSING sends 500 USD receives 5000000 USDC
    10.00 USD
    (APPROVED)
    |}];
  return ()
;;

let%expect_test "errors" =
  let show response =
    print_s
      [%sexp
        (Grid.decode_response ~what:"quote" G.Quote.t_of_yojson response
         : G.Quote.t Api_error.result)]
  in
  show (Fixture.response ~status:404 "grid/error_404.json");
  show
    { status = 429
    ; headers = [ "Retry-After", "1.5" ]
    ; body = {|{"code":"RATE_LIMITED","reason":"slow down"}|}
    };
  show { status = 200; headers = []; body = {|{"id": 1}|} };
  [%expect
    {|
    (Error
     (Http (status 404) (code (QUOTE_NOT_FOUND))
      (reason ("Quote 00000000-0000-0000-0000-000000000000 not found"))
      (request_id (req-fixture))
      (body
        "{\
       \n \"code\": \"QUOTE_NOT_FOUND\",\
       \n \"reason\": \"Quote 00000000-0000-0000-0000-000000000000 not found\"\
       \n}\
       \n")))
    (Error (Rate_limited (retry_after (1.5s)) (request_id ())))
    (Error
     (Decode (what quote)
      (message
       "(\"Of_yojson_error (Failure(\\\"string_of_yojson: string needed\\\"), 1)\")")))
    |}];
  return ()
;;

let%expect_test "writes are refused when the platform is not a sandbox" =
  let not_sandbox =
    let json = Yojson.Safe.from_string (Fixture.read "grid/config.json") in
    let json =
      match json with
      | `Assoc fields ->
        `Assoc
          (List.map fields ~f:(fun (k, v) ->
             match k with
             | "umaDomain" -> k, `String "example.umaaas.uma.money"
             | "proxyUmaSubdomain" -> k, `String "example"
             | _ -> k, v))
      | other -> other
    in
    { Transport.Response.status = 200; headers = []; body = Yojson.Safe.to_string json }
  in
  let config = Config.create ~client_id:"id" ~client_secret:"secret" () in
  let grid =
    Grid.create
      ~log:ignore
      ~transport:(Fixture.fake_transport [ "/config", not_sandbox ])
      config
  in
  let%bind result =
    Grid.create_quote
      grid
      ~source_account_id:"InternalAccount:1"
      ~destination:(Account "InternalAccount:2")
      ~locked_side:`Sending
      ~amount:100
      ~idempotency_key:"k"
  in
  print_s [%sexp (result : G.Quote.t Api_error.result)];
  [%expect
    {|
    GET /grid/2025-10-13/config
    (Error
     (Refused
      "platform does not look like a Grid sandbox; build the config with ~live:true to allow writes"))
    |}];
  (* A sandbox platform passes the check once and the write is sent. *)
  let grid =
    Grid.create
      ~log:ignore
      ~transport:
        (Fixture.fake_transport
           [ "/config", Fixture.response "grid/config.json"
           ; "/quotes", Fixture.response "grid/create_quote.json"
           ; "/execute", Fixture.response "grid/execute_quote.json"
           ])
      config
  in
  let%bind quote =
    Grid.create_quote
      grid
      ~source_account_id:"InternalAccount:1"
      ~destination:(Account "InternalAccount:2")
      ~locked_side:`Sending
      ~amount:500
      ~idempotency_key:"k"
  in
  let quote = Api_error.ok_exn quote in
  let%bind executed = Grid.execute_quote grid ~quote_id:quote.id ~idempotency_key:"k2" in
  print_s [%sexp ((Api_error.ok_exn executed).status : string)];
  [%expect
    {|
    GET /grid/2025-10-13/config
    POST /grid/2025-10-13/quotes
    POST /grid/2025-10-13/quotes/Quote:00000000-0000-0000-0000-000000000001/execute
    PROCESSING
    |}];
  return ()
;;

let%expect_test "all_pages follows cursors" =
  let pages =
    String.Map.of_alist_exn
      [ "", ([ 1; 2 ], Some "a"); "a", ([ 3; 4 ], Some "b"); "b", ([ 5 ], None) ]
  in
  let fetch ~cursor =
    let data, next_cursor = Map.find_exn pages (Option.value cursor ~default:"") in
    return
      (Ok
         { G.Page.data
         ; has_more = Option.is_some next_cursor
         ; next_cursor
         ; total_count = None
         })
  in
  let%bind all = Grid.all_pages fetch in
  let%bind two = Grid.all_pages ~max_pages:2 fetch in
  print_s [%sexp (all : int list Api_error.result), (two : int list Api_error.result)];
  [%expect {| ((Ok (1 2 3 4 5)) (Ok (1 2 3 4))) |}];
  return ()
;;
