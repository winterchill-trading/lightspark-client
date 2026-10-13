open! Core
open! Async
open Lightning_types

let member = Yojson.Safe.Util.member

(* Runs [f] on the data object, turning decoder exceptions into [Decode] errors. *)
let decode what f data =
  match f data with
  | x -> Ok x
  | exception exn ->
    Error (Api_error.Decode { what; message = String.prefix (Exn.to_string exn) 500 })
;;

let path names json = List.fold names ~init:json ~f:(fun json name -> member name json)
let opt name f = Option.map ~f:(fun v -> name, f v)
let int v = `Int v
let str v = `String v

module Decode = struct
  let current_account =
    decode "current_account" (fun data ->
      Account.t_of_yojson (member "current_account" data))
  ;;

  let nodes =
    decode "nodes" (fun data ->
      Connection.of_json
        ~prefix:"account_to_nodes_connection"
        Node.t_of_yojson
        (path [ "current_account"; "nodes" ] data))
  ;;

  let wallets =
    decode "wallets" (fun data ->
      Connection.of_json
        ~prefix:"account_to_wallets_connection"
        Wallet.t_of_yojson
        (path [ "current_account"; "wallets" ] data))
  ;;

  let transactions =
    decode "transactions" (fun data ->
      Connection.of_json
        ~prefix:"account_to_transactions_connection"
        Transaction.t_of_yojson
        (path [ "current_account"; "transactions" ] data))
  ;;

  let invoice_for_payment_hash =
    decode "invoice_for_payment_hash" (fun data ->
      Invoice.t_of_yojson (path [ "invoice_for_payment_hash"; "invoice" ] data))
  ;;

  let decoded_payment_request =
    decode "decoded_payment_request" (fun data ->
      let request = member "decoded_payment_request" data in
      match member "__typename" request with
      | `String "InvoiceData" -> Invoice_data.t_of_yojson request
      | other ->
        failwithf "unsupported payment request type %s" (Yojson.Safe.to_string other) ())
  ;;

  let node_network =
    decode "node_network" (fun data ->
      match member "lightspark_node_bitcoin_network" (member "entity" data) with
      | `String network -> Some network
      | _ -> None)
  ;;

  let create_invoice =
    decode "create_invoice" (fun data ->
      Invoice.t_of_yojson (path [ "create_invoice"; "invoice" ] data))
  ;;

  let create_test_mode_invoice =
    decode "create_test_mode_invoice" (fun data ->
      Yojson.Safe.Util.to_string
        (path [ "create_test_mode_invoice"; "encoded_payment_request" ] data))
  ;;

  let create_test_mode_payment =
    decode "create_test_mode_payment" (fun data ->
      Transaction.t_of_yojson
        (path [ "create_test_mode_payment"; "incoming_payment" ] data))
  ;;

  let fund_node =
    decode "fund_node" (fun data ->
      Currency_amount.t_of_yojson (path [ "fund_node"; "amount" ] data))
  ;;

  let pay_invoice =
    decode "pay_invoice" (fun data ->
      Transaction.t_of_yojson (path [ "pay_invoice"; "payment" ] data))
  ;;
end

let run graphql document variables decoder =
  Graphql.execute graphql ~query:document ~variables:(List.filter_opt variables)
  >>| Result.bind ~f:decoder
;;

let current_account graphql =
  run graphql Documents.current_account [] Decode.current_account
;;

let nodes ?first ?after ?bitcoin_networks graphql =
  run
    graphql
    Documents.account_nodes
    [ opt "first" int first
    ; opt "after" str after
    ; opt "bitcoin_networks" (fun l -> `List (List.map l ~f:str)) bitcoin_networks
    ]
    Decode.nodes
;;

let wallets ?first ?after graphql =
  run
    graphql
    Documents.account_wallets
    [ opt "first" int first; opt "after" str after ]
    Decode.wallets
;;

let transactions ?first ?after ?bitcoin_network ?node_id graphql =
  run
    graphql
    Documents.account_transactions
    [ opt "first" int first
    ; opt "after" str after
    ; opt "bitcoin_network" str bitcoin_network
    ; opt "lightning_node_id" str node_id
    ]
    Decode.transactions
;;

let invoice_for_payment_hash graphql ~payment_hash =
  run
    graphql
    Documents.invoice_for_payment_hash
    [ Some ("payment_hash", str payment_hash) ]
    Decode.invoice_for_payment_hash
;;

let decode_payment_request graphql ~encoded_payment_request =
  run
    graphql
    Documents.decoded_payment_request
    [ Some ("encoded_payment_request", str encoded_payment_request) ]
    Decode.decoded_payment_request
;;

let node_network graphql ~node_id =
  run graphql Documents.node_network [ Some ("node_id", str node_id) ] Decode.node_network
;;

(* Outside [Live] mode every write must target a REGTEST node. *)
let guarded graphql ~node_id ~what f =
  if Config.is_live (Graphql.config graphql)
  then f ()
  else (
    match%bind node_network graphql ~node_id with
    | Error _ as e -> return e
    | Ok (Some "REGTEST") -> f ()
    | Ok network ->
      return
        (Error
           (Api_error.Refused
              (sprintf
                 "%s: node %s is on %s, not REGTEST; build the config with ~live:true to \
                  allow this"
                 what
                 node_id
                 (Option.value network ~default:"an unknown network")))))
;;

let create_invoice ?memo ?expiry_secs graphql ~node_id ~amount_msats =
  guarded graphql ~node_id ~what:"create_invoice" (fun () ->
    run
      graphql
      Documents.create_invoice
      [ Some ("node_id", str node_id)
      ; Some ("amount_msats", int amount_msats)
      ; opt "memo" str memo
      ; opt "expiry_secs" int expiry_secs
      ]
      Decode.create_invoice)
;;

let create_test_mode_invoice ?memo graphql ~node_id ~amount_msats =
  guarded graphql ~node_id ~what:"create_test_mode_invoice" (fun () ->
    run
      graphql
      Documents.create_test_mode_invoice
      [ Some ("local_node_id", str node_id)
      ; Some ("amount_msats", int amount_msats)
      ; opt "memo" str memo
      ]
      Decode.create_test_mode_invoice)
;;

let create_test_mode_payment ?amount_msats graphql ~node_id ~encoded_invoice =
  guarded graphql ~node_id ~what:"create_test_mode_payment" (fun () ->
    run
      graphql
      Documents.create_test_mode_payment
      [ Some ("local_node_id", str node_id)
      ; Some ("encoded_invoice", str encoded_invoice)
      ; opt "amount_msats" int amount_msats
      ]
      Decode.create_test_mode_payment)
;;

let fund_node ?amount_sats graphql ~node_id =
  guarded graphql ~node_id ~what:"fund_node" (fun () ->
    run
      graphql
      Documents.fund_node
      [ Some ("node_id", str node_id); opt "amount_sats" int amount_sats ]
      Decode.fund_node)
;;

let pay_invoice
  ?amount_msats
  ?idempotency_key
  graphql
  ~node_id
  ~encoded_invoice
  ~timeout_secs
  ~maximum_fees_msats
  =
  guarded graphql ~node_id ~what:"pay_invoice" (fun () ->
    run
      graphql
      Documents.pay_invoice
      [ Some ("node_id", str node_id)
      ; Some ("encoded_invoice", str encoded_invoice)
      ; Some ("timeout_secs", int timeout_secs)
      ; Some ("maximum_fees_msats", int maximum_fees_msats)
      ; opt "amount_msats" int amount_msats
      ; opt "idempotency_key" str idempotency_key
      ]
      Decode.pay_invoice)
;;
