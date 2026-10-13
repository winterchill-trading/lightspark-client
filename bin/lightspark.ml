open! Core
open! Async
open Lightspark_client
module L = Lightning_types
module G = Grid_types

type format =
  | Json
  | Sexp

let format_flag =
  let%map_open.Command sexp = flag "sexp" no_arg ~doc:" print sexps instead of JSON" in
  if sexp then Sexp else Json
;;

let live_flag =
  Command.Param.flag
    "live"
    Command.Param.no_arg
    ~doc:" allow writes outside sandbox / test mode (default: refuse)"
;;

let config ~live = Config.of_env ~live () |> Or_error.ok_exn

(* Prints a result or exits 1 with the error; the error is already redacted. *)
let output format ~json ~sexp result =
  match result with
  | Ok v ->
    (match format with
     | Json -> print_endline (Yojson.Safe.pretty_to_string (json v))
     | Sexp -> print_s (sexp v));
    return ()
  | Error e ->
    Print.eprint_s [%sexp (e : Api_error.t)];
    exit 1
;;

let list_json f l = `List (List.map l ~f)

let connection_json f (c : _ L.Connection.t) =
  `Assoc
    [ "count", `Int c.count
    ; "has_next_page", `Bool c.page_info.has_next_page
    ; ( "end_cursor"
      , Option.value_map c.page_info.end_cursor ~default:`Null ~f:(fun s -> `String s) )
    ; "entities", list_json f c.entities
    ]
;;

let page_json f (p : _ G.Page.t) =
  `Assoc
    [ "has_more", `Bool p.has_more
    ; "next_cursor", Option.value_map p.next_cursor ~default:`Null ~f:(fun s -> `String s)
    ; "total_count", Option.value_map p.total_count ~default:`Null ~f:(fun n -> `Int n)
    ; "data", list_json f p.data
    ]
;;

let graphql_command ~summary ?(live = false) param run =
  Command.async
    ~summary
    (let%map_open.Command format = format_flag
     and live_flag = if live then live_flag else return false
     and f = param in
     fun () ->
       let graphql = Graphql.create (config ~live:live_flag) in
       run format graphql f)
;;

let lightning_commands =
  let first = Command.Param.(flag "limit" (optional int) ~doc:"N page size") in
  let after = Command.Param.(flag "after" (optional string) ~doc:"CURSOR page cursor") in
  let node_id = Command.Param.(flag "node-id" (required string) ~doc:"ID node id") in
  [ ( "account"
    , graphql_command
        ~summary:"current account"
        (Command.Param.return ())
        (fun fmt g () ->
           Lightning.current_account g
           >>= output fmt ~json:L.Account.yojson_of_t ~sexp:L.Account.sexp_of_t) )
  ; ( "nodes"
    , graphql_command
        ~summary:"nodes and balances"
        Command.Param.(both first after)
        (fun fmt g (first, after) ->
          Lightning.nodes ?first ?after g
          >>= output
                fmt
                ~json:(connection_json L.Node.yojson_of_t)
                ~sexp:[%sexp_of: L.Node.t L.Connection.t]) )
  ; ( "wallets"
    , graphql_command
        ~summary:"wallets"
        Command.Param.(both first after)
        (fun fmt g (first, after) ->
          Lightning.wallets ?first ?after g
          >>= output
                fmt
                ~json:(connection_json L.Wallet.yojson_of_t)
                ~sexp:[%sexp_of: L.Wallet.t L.Connection.t]) )
  ; ( "transactions"
    , graphql_command
        ~summary:"transactions, newest first"
        Command.Param.(both first after)
        (fun fmt g (first, after) ->
          Lightning.transactions ?first ?after g
          >>= output
                fmt
                ~json:(connection_json L.Transaction.yojson_of_t)
                ~sexp:[%sexp_of: L.Transaction.t L.Connection.t]) )
  ; ( "invoice"
    , Command.group
        ~summary:"invoices"
        [ ( "create"
          , graphql_command
              ~summary:"create an invoice (REGTEST nodes unless -live)"
              ~live:true
              Command.Param.(
                both
                  node_id
                  (both
                     (flag "amount-msats" (required int) ~doc:"MSATS amount")
                     (flag "memo" (optional string) ~doc:"TEXT memo")))
              (fun fmt g (node_id, (amount_msats, memo)) ->
                Lightning.create_invoice ?memo g ~node_id ~amount_msats
                >>= output fmt ~json:L.Invoice.yojson_of_t ~sexp:L.Invoice.sexp_of_t) )
        ; ( "lookup"
          , graphql_command
              ~summary:"invoice for a payment hash"
              Command.Param.(
                flag "payment-hash" (required string) ~doc:"HEX payment hash")
              (fun fmt g payment_hash ->
                Lightning.invoice_for_payment_hash g ~payment_hash
                >>= output fmt ~json:L.Invoice.yojson_of_t ~sexp:L.Invoice.sexp_of_t) )
        ; ( "test-create"
          , graphql_command
              ~summary:"test-mode invoice a REGTEST node can pay"
              ~live:true
              Command.Param.(
                both node_id (flag "amount-msats" (required int) ~doc:"MSATS amount"))
              (fun fmt g (node_id, amount_msats) ->
                Lightning.create_test_mode_invoice g ~node_id ~amount_msats
                >>= output fmt ~json:(fun s -> `String s) ~sexp:String.sexp_of_t) )
        ; ( "test-pay"
          , graphql_command
              ~summary:"simulate an incoming payment to one of our REGTEST invoices"
              ~live:true
              Command.Param.(
                both node_id (flag "invoice" (required string) ~doc:"BOLT11 invoice"))
              (fun fmt g (node_id, encoded_invoice) ->
                Lightning.create_test_mode_payment g ~node_id ~encoded_invoice
                >>= output
                      fmt
                      ~json:L.Transaction.yojson_of_t
                      ~sexp:L.Transaction.sexp_of_t) )
        ] )
  ; ( "fund-node"
    , graphql_command
        ~summary:"add test funds to a REGTEST node"
        ~live:true
        Command.Param.(
          both node_id (flag "amount-sats" (optional int) ~doc:"SATS default 10,000,000"))
        (fun fmt g (node_id, amount_sats) ->
          Lightning.fund_node ?amount_sats g ~node_id
          >>= output
                fmt
                ~json:L.Currency_amount.yojson_of_t
                ~sexp:L.Currency_amount.sexp_of_t) )
  ]
;;

let grid_command ~summary ?(live = false) param run =
  Command.async
    ~summary
    (let%map_open.Command format = format_flag
     and live_flag = if live then live_flag else return false
     and f = param in
     fun () ->
       let grid = Grid.create (config ~live:live_flag) in
       run format grid f)
;;

let grid_commands =
  let open Command.Param in
  let limit = flag "limit" (optional int) ~doc:"N page size (1..100)" in
  let cursor = flag "cursor" (optional string) ~doc:"CURSOR page cursor" in
  let id = flag "id" (required string) ~doc:"ID object id" in
  [ ( "config"
    , grid_command ~summary:"platform configuration" (return ()) (fun fmt g () ->
        Grid.platform_config g
        >>= output
              fmt
              ~json:G.Platform_config.yojson_of_t
              ~sexp:G.Platform_config.sexp_of_t) )
  ; ( "customers"
    , grid_command ~summary:"customers" (both limit cursor) (fun fmt g (limit, cursor) ->
        Grid.customers ?limit ?cursor g
        >>= output
              fmt
              ~json:(page_json G.Customer.yojson_of_t)
              ~sexp:[%sexp_of: G.Customer.t G.Page.t]) )
  ; ( "accounts"
    , grid_command
        ~summary:"customer internal accounts"
        (both
           (both limit cursor)
           (flag "customer-id" (optional string) ~doc:"ID only this customer"))
        (fun fmt g ((limit, cursor), customer_id) ->
          Grid.customer_internal_accounts ?limit ?cursor ?customer_id g
          >>= output
                fmt
                ~json:(page_json G.Internal_account.yojson_of_t)
                ~sexp:[%sexp_of: G.Internal_account.t G.Page.t]) )
  ; ( "platform-accounts"
    , grid_command ~summary:"platform internal accounts" (return ()) (fun fmt g () ->
        Grid.platform_internal_accounts g
        >>= output
              fmt
              ~json:(page_json G.Internal_account.yojson_of_t)
              ~sexp:[%sexp_of: G.Internal_account.t G.Page.t]) )
  ; ( "transactions"
    , grid_command
        ~summary:"transactions, newest first"
        (both limit cursor)
        (fun fmt g (limit, cursor) ->
           Grid.transactions ?limit ?cursor g
           >>= output
                 fmt
                 ~json:(page_json G.Transaction.yojson_of_t)
                 ~sexp:[%sexp_of: G.Transaction.t G.Page.t]) )
  ; ( "transaction"
    , grid_command ~summary:"one transaction" id (fun fmt g id ->
        Grid.transaction g ~id
        >>= output fmt ~json:G.Transaction.yojson_of_t ~sexp:G.Transaction.sexp_of_t) )
  ; ( "rates"
    , grid_command
        ~summary:"cached exchange rates"
        (both
           (flag "source" (optional string) ~doc:"CCY source currency")
           (flag "destination" (optional string) ~doc:"CCY destination currency"))
        (fun fmt g (source_currency, destination_currency) ->
          Grid.exchange_rates ?source_currency ?destination_currency g
          >>= output
                fmt
                ~json:(list_json G.Exchange_rate.yojson_of_t)
                ~sexp:[%sexp_of: G.Exchange_rate.t list]) )
  ; ( "quote"
    , grid_command ~summary:"one quote" id (fun fmt g id ->
        Grid.quote g ~id >>= output fmt ~json:G.Quote.yojson_of_t ~sexp:G.Quote.sexp_of_t)
    )
  ; ( "sandbox-fund"
    , grid_command
        ~summary:"fund an internal account (sandbox keys only)"
        (both
           (flag "account-id" (required string) ~doc:"ID internal account")
           (flag "amount" (required int) ~doc:"N smallest currency unit"))
        (fun fmt g (account_id, amount) ->
          Grid.sandbox_fund_internal_account g ~account_id ~amount
          >>= output
                fmt
                ~json:G.Internal_account.yojson_of_t
                ~sexp:G.Internal_account.sexp_of_t) )
  ; ( "send-uma"
    , grid_command
        ~summary:"quote and execute a payment from an internal account to a UMA address"
        ~live:true
        (both
           (both
              (flag "account-id" (required string) ~doc:"ID source internal account")
              (flag "to" (required string) ~doc:"UMA e.g. $success.usd@sandbox.uma.money"))
           (both
              (flag "currency" (required string) ~doc:"CCY receiving currency")
              (flag "amount" (required int) ~doc:"N sending amount, smallest unit")))
        (fun fmt g ((source_account_id, address), (currency, amount)) ->
          let idempotency_key = Uuid_unix.create () |> Uuid.to_string in
          Grid.create_quote
            g
            ~source_account_id
            ~destination:(Uma_address { address; currency })
            ~locked_side:`Sending
            ~amount
            ~idempotency_key
          >>= function
          | Error _ as e -> output fmt ~json:G.Quote.yojson_of_t ~sexp:G.Quote.sexp_of_t e
          | Ok quote ->
            Grid.execute_quote
              g
              ~quote_id:quote.id
              ~idempotency_key:(idempotency_key ^ "-x")
            >>= output fmt ~json:G.Quote.yojson_of_t ~sexp:G.Quote.sexp_of_t) )
  ]
;;

let () =
  Command.group
    ~summary:"Lightspark GraphQL and Grid API client (credentials from LIGHTSPARK_* env)"
    (lightning_commands @ [ "grid", Command.group ~summary:"Grid API" grid_commands ])
  |> Command_unix.run
;;
