(* Prints only counts, statuses and error kinds: never ids, names, amounts tied to a
   person, or credentials. *)

open! Core
open! Async
open Lightspark_client
module G = Grid_types

let failures = ref 0

let check name result ~describe =
  (match result with
   | Ok v -> printf "ok   %s: %s\n" name (describe v)
   | Error (e : Api_error.t) ->
     incr failures;
     printf "FAIL %s: %s\n" name (Sexp.to_string [%sexp (e : Api_error.t)]));
  result
;;

let page_desc (p : _ G.Page.t) =
  sprintf "%d items, has_more=%b" (List.length p.data) p.has_more
;;

let grid_reads grid =
  let%bind config =
    Grid.platform_config grid
    >>| check "grid config" ~describe:(fun (c : G.Platform_config.t) ->
      sprintf
        "%d currencies, sandbox=%b"
        (List.length c.supported_currencies)
        (G.Platform_config.looks_like_sandbox c))
  in
  ignore (config : _ Result.t);
  let%bind (_ : _ Result.t) =
    Grid.customers ~limit:2 grid >>| check "grid customers" ~describe:page_desc
  in
  let%bind (_ : _ Result.t) =
    Grid.customer_internal_accounts ~limit:2 grid
    >>| check "grid internal accounts" ~describe:page_desc
  in
  let%bind (_ : _ Result.t) =
    Grid.platform_internal_accounts grid
    >>| check "grid platform accounts" ~describe:page_desc
  in
  let%bind (_ : _ Result.t) =
    Grid.all_pages ~max_pages:3 (fun ~cursor -> Grid.transactions ~limit:2 ?cursor grid)
    >>| check "grid transactions (3 pages of 2)" ~describe:(fun l ->
      let ids = List.map l ~f:(fun (t : G.Transaction.t) -> t.id) in
      sprintf
        "%d items, %d distinct"
        (List.length ids)
        (List.length (List.dedup_and_sort ids ~compare:String.compare)))
  in
  let%map (_ : _ Result.t) =
    Grid.exchange_rates ~source_currency:"USD" grid
    >>| check "grid exchange rates" ~describe:(fun l ->
      sprintf "%d corridors" (List.length l))
  in
  ()
;;

let graphql_reads graphql =
  match%map Lightning.current_account graphql with
  | Ok _ -> printf "ok   graphql current_account\n"
  | Error
      (Graphql { errors = { error_name = Some "AuthenticationException"; _ } :: _; _ }) ->
    (* Expected with a Grid token: the GraphQL server API needs its own token. *)
    printf "skip graphql current_account: token not valid for the GraphQL API\n"
  | Error e ->
    incr failures;
    printf "FAIL graphql current_account: %s\n" (Sexp.to_string [%sexp (e : Api_error.t)])
;;

(* Sandbox write flow on objects created in this run: a customer, a sandbox deposit into
   its USD account, and a payment to the sandbox success UMA address. *)
let grid_writes grid =
  let run_id = Uuid_unix.create () |> Uuid.to_string in
  let ( let*! ) d f =
    match%bind d with
    | Ok v -> f v
    | Error (_ : Api_error.t) -> return ()
  in
  let*! customer =
    Grid.create_individual_customer
      grid
      ~platform_customer_id:("wc-sandbox-" ^ String.prefix run_id 8)
      ~full_name:"Sandbox Test"
      ~birth_date:"1990-01-15"
      ~nationality:"US"
      ~region:"US"
      ~currencies:[ "USD" ]
      ~idempotency_key:("customer-" ^ run_id)
    >>| check "grid create customer" ~describe:(fun (c : G.Customer.t) ->
      sprintf "kyc=%s" (Option.value c.kyc_status ~default:"-"))
  in
  let*! accounts =
    Grid.customer_internal_accounts ~customer_id:customer.id ~currency:"USD" grid
    >>| check "grid customer accounts" ~describe:page_desc
  in
  match List.hd accounts.data with
  | None ->
    incr failures;
    printf "FAIL grid customer accounts: no USD account\n";
    return ()
  | Some account ->
    let*! funded =
      Grid.sandbox_fund_internal_account grid ~account_id:account.id ~amount:1000
      >>| check "grid sandbox fund" ~describe:(fun (a : G.Internal_account.t) ->
        G.Amount.to_string_hum a.balance)
    in
    ignore (funded : G.Internal_account.t);
    let*! quote =
      Grid.create_quote
        grid
        ~source_account_id:account.id
        ~destination:
          (Uma_address { address = "$success.usd@sandbox.uma.money"; currency = "USD" })
        ~locked_side:`Sending
        ~amount:500
        ~idempotency_key:("quote-" ^ run_id)
      >>| check "grid create quote" ~describe:(fun (q : G.Quote.t) ->
        sprintf "status=%s sending=%d" q.status q.total_sending_amount)
    in
    let*! executed =
      Grid.execute_quote grid ~quote_id:quote.id ~idempotency_key:("execute-" ^ run_id)
      >>| check "grid execute quote" ~describe:(fun (q : G.Quote.t) ->
        sprintf "status=%s" q.status)
    in
    (match executed.transaction_id with
     | None -> return ()
     | Some id ->
       let%map (_ : _ Result.t) =
         Grid.transaction grid ~id
         >>| check
               "grid transaction after execute"
               ~describe:(fun (t : G.Transaction.t) ->
                 sprintf "type=%s status=%s" t.type_ t.status)
       in
       ())
;;

let main () =
  match Config.of_env () with
  | Error _ ->
    print_endline
      "skip live checks: LIGHTSPARK_CLIENT_ID / LIGHTSPARK_CLIENT_SECRET not set";
    return ()
  | Ok config ->
    let log (_ : Sexp.t) = () in
    let grid = Grid.create ~log config in
    let%bind () = grid_reads grid in
    let%bind () = graphql_reads (Graphql.create ~log config) in
    let%bind () =
      match Sys.getenv "LIGHTSPARK_LIVE_WRITES" with
      | Some "1" -> grid_writes grid
      | _ ->
        print_endline "skip sandbox writes: set LIGHTSPARK_LIVE_WRITES=1";
        return ()
    in
    if !failures > 0 then exit 1 else return ()
;;

let () =
  Command.async ~summary:"live API checks" (Command.Param.return main) |> Command_unix.run
;;
