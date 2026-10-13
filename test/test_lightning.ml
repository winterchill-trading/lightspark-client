(* The GraphQL fixtures follow the official SDK response shapes; the sandbox token we have
   is a Grid token, so only the 401 body was recorded live. *)

open! Core
open! Async
open Lightspark_client
module L = Lightning_types

let data path = Graphql.decode_response (Fixture.response path) |> Api_error.ok_exn

let%expect_test "reads" =
  print_s
    [%sexp
      (Lightning.Decode.current_account (data "graphql/current_account.json")
       : L.Account.t Api_error.result)];
  let nodes = Lightning.Decode.nodes (data "graphql/nodes.json") |> Api_error.ok_exn in
  List.iter nodes.entities ~f:(fun (n : L.Node.t) ->
    printf
      "%s %s %s owned=%s\n"
      n.typename
      n.bitcoin_network
      n.display_name
      (Option.value_map n.balances ~default:"-" ~f:(fun b ->
         sprintf "%d %s" b.owned.original_value b.owned.original_unit)));
  let wallets =
    Lightning.Decode.wallets (data "graphql/wallets.json") |> Api_error.ok_exn
  in
  print_s [%sexp (wallets.count : int), (wallets.page_info : L.Page_info.t)];
  let txs =
    Lightning.Decode.transactions (data "graphql/transactions.json") |> Api_error.ok_exn
  in
  print_s [%sexp (txs.page_info : L.Page_info.t)];
  List.iter txs.entities ~f:(fun (t : L.Transaction.t) ->
    printf
      "%s %s %d %s\n"
      t.typename
      t.status
      t.amount.original_value
      t.amount.original_unit);
  let invoice =
    Lightning.Decode.invoice_for_payment_hash
      (data "graphql/invoice_for_payment_hash.json")
    |> Api_error.ok_exn
  in
  print_s [%sexp (invoice.status : string), (invoice.data.amount : L.Currency_amount.t)];
  [%expect
    {|
    (Ok
     ((id Account:00000000-0000-0000-0000-000000000001)
      (created_at 2026-01-01T00:00:00+00:00)
      (updated_at 2026-01-02T00:00:00+00:00) (name ("Example Account"))))
    LightsparkNodeWithRemoteSigning REGTEST regtest-node owned=10000000 SATOSHI
    LightsparkNodeWithOSK MAINNET mainnet-node owned=-
    (1 ((has_next_page false) (end_cursor ())))
    ((has_next_page true) (end_cursor (cursor-2)))
    IncomingPayment SUCCESS 100000 MILLISATOSHI
    Deposit PENDING 10000000 SATOSHI
    (OPEN
     ((original_value 100000) (original_unit MILLISATOSHI)
      (preferred_currency_unit USD) (preferred_currency_value_rounded 0)
      (preferred_currency_value_approx 0)))
    |}];
  return ()
;;

let%expect_test "writes" =
  print_s
    [%sexp
      (Lightning.Decode.create_test_mode_invoice
         (data "graphql/create_test_mode_invoice.json")
       : string Api_error.result)];
  print_s
    [%sexp
      (Lightning.Decode.fund_node (data "graphql/fund_node.json")
       : L.Currency_amount.t Api_error.result)];
  [%expect
    {|
    (Ok lnbcrt1u1pexample)
    (Ok
     ((original_value 10000000) (original_unit SATOSHI)
      (preferred_currency_unit USD) (preferred_currency_value_rounded 0)
      (preferred_currency_value_approx 0)))
    |}];
  return ()
;;

let%expect_test "live 401 for a token of the wrong kind" =
  print_s
    [%sexp
      (Graphql.decode_response
         (Fixture.response ~status:401 "graphql/unauthenticated.json")
       |> Result.map ~f:Yojson.Safe.to_string
       : string Api_error.result)];
  [%expect
    {|
    (Error
     (Graphql (status 401)
      (errors
       (((message "Not logged in.") (path (current_account))
         (error_name (AuthenticationException)))))
      (request_id (req-fixture))))
    |}];
  return ()
;;

let%expect_test "writes to a non-REGTEST node are refused before the mutation" =
  let config = Config.create ~client_id:"id" ~client_secret:"secret" () in
  let graphql =
    Graphql.create
      ~log:ignore
      ~transport:
        (Fixture.fake_transport
           [ "/graphql/server/2023-09-13", Fixture.response "graphql/node_network.json" ])
      config
  in
  let%bind result =
    Lightning.create_invoice graphql ~node_id:"LightsparkNodeWithOSK:2" ~amount_msats:1000
  in
  print_s [%sexp (result : L.Invoice.t Api_error.result)];
  [%expect
    {|
    POST /graphql/server/2023-09-13
    (Error
     (Refused
      "create_invoice: node LightsparkNodeWithOSK:2 is on MAINNET, not REGTEST; build the config with ~live:true to allow this"))
    |}];
  return ()
;;
