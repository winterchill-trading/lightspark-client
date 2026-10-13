open! Core
open! Async

module Meth = struct
  type t =
    [ `GET
    | `POST
    | `PUT
    | `PATCH
    | `DELETE
    ]
  [@@deriving sexp_of, compare, equal]
end

module Request = struct
  type t =
    { meth : Meth.t
    ; uri : Uri.t
    ; headers : (string * string) list
    ; body : string option
    ; idempotent : bool
    }

  let sexp_of_t t =
    [%sexp
      { meth : Meth.t = t.meth
      ; uri = (Uri.to_string t.uri : string)
      ; headers = (Auth.redact_headers t.headers : (string * string) list)
      ; idempotent : bool = t.idempotent
      }]
  ;;
end

module Response = struct
  type t =
    { status : int
    ; headers : (string * string) list
    ; body : string
    }
  [@@deriving sexp_of]

  let header t name =
    List.find_map t.headers ~f:(fun (k, v) ->
      Option.some_if (String.Caseless.equal k name) v)
  ;;

  let request_id t = header t "x-request-id"

  let retry_after t =
    Option.bind (header t "retry-after") ~f:(fun v ->
      match Float.of_string_opt (String.strip v) with
      | Some secs when Float.(secs >= 0.) -> Some (Time_ns.Span.of_sec secs)
      | _ -> None)
  ;;
end

type t = Request.t -> (Response.t, string) Result.t Deferred.t

(* async_ssl verifies the chain against the system roots by default (Verify_peer), but
   neither it nor conduit-async checks that the certificate names the host we dialled;
   without this check any valid certificate for another domain would be accepted. *)
let ssl_config uri =
  let host = Option.value (Uri.host uri) ~default:"" in
  let verify conn =
    return
      (match Async_ssl.Ssl.Connection.peer_certificate conn with
       | Some (Ok _) ->
         Result.is_ok (Async_ssl.Ssl.Connection.check_peer_certificate_host conn host)
       | Some (Error _) | None -> false)
  in
  Conduit_async.V2.Ssl.Config.create
    ~hostname:host
    ~verify_modes:[ Async_ssl.Verify_mode.Verify_peer ]
    ~verify
    ()
;;

let cohttp ?(timeout = Time_ns.Span.of_int_sec 30) () (request : Request.t) =
  let headers = Cohttp.Header.of_list request.headers in
  let ssl_config =
    match Uri.scheme request.uri with
    | Some "https" -> Some (ssl_config request.uri)
    | _ -> None
  in
  let body = Option.map request.body ~f:Cohttp_async.Body.of_string in
  let call () =
    let%bind response, body =
      Cohttp_async.Client.call
        ?ssl_config
        ~headers
        ?body
        (request.meth :> Cohttp.Code.meth)
        request.uri
    in
    let%map body = Cohttp_async.Body.to_string body in
    { Response.status = Cohttp.Code.code_of_status (Cohttp.Response.status response)
    ; headers = Cohttp.Header.to_list (Cohttp.Response.headers response)
    ; body
    }
  in
  match%map Clock_ns.with_timeout timeout (Monitor.try_with ~extract_exn:true call) with
  | `Timeout -> Error (sprintf "timeout after %s" (Time_ns.Span.to_string_hum timeout))
  | `Result (Ok response) -> Ok response
  | `Result (Error exn) -> Error (Exn.to_string exn)
;;

module Retry = struct
  type policy =
    { max_attempts : int
    ; initial_backoff : Time_ns.Span.t
    ; max_backoff : Time_ns.Span.t
    }
  [@@deriving sexp_of]

  let default =
    { max_attempts = 4
    ; initial_backoff = Time_ns.Span.of_int_ms 250
    ; max_backoff = Time_ns.Span.of_int_sec 5
    }
  ;;

  let no_retry = { default with max_attempts = 1 }

  let retryable_status = function
    | 408 | 425 | 429 | 500 | 502 | 503 | 504 -> true
    | _ -> false
  ;;

  let run
    ?(policy = default)
    ?(sleep = Clock_ns.after)
    ?(log = fun sexp -> Log.Global.info_s sexp)
    (transport : t)
    (request : Request.t)
    =
    let rec attempt n backoff =
      let%bind result = transport request in
      let retry ~why ~wait =
        if n >= policy.max_attempts
        then return result
        else (
          let wait = Option.value wait ~default:backoff in
          log
            [%message
              "lightspark retry"
                ~meth:(request.meth : Meth.t)
                ~uri:(Uri.path request.uri : string)
                (why : string)
                ~attempt:(n : int)
                (wait : Time_ns.Span.t)];
          let%bind () = sleep wait in
          attempt
            (n + 1)
            (Time_ns.Span.min policy.max_backoff (Time_ns.Span.scale backoff 2.)))
      in
      match result with
      | Ok response when response.status = 429 ->
        retry
          ~why:
            (sprintf
               "429 request_id=%s"
               (Option.value (Response.request_id response) ~default:"-"))
          ~wait:(Response.retry_after response)
      | Ok response when retryable_status response.status && request.idempotent ->
        retry
          ~why:
            (sprintf
               "%d request_id=%s"
               response.status
               (Option.value (Response.request_id response) ~default:"-"))
          ~wait:(Response.retry_after response)
      | Ok _ -> return result
      | Error message when request.idempotent -> retry ~why:message ~wait:None
      | Error _ -> return result
    in
    attempt 1 policy.initial_backoff
  ;;
end

let%expect_test "retry honours idempotency and Retry-After" =
  let script = ref [] in
  let transport (_ : Request.t) =
    match !script with
    | [] -> failwith "script exhausted"
    | x :: rest ->
      script := rest;
      return x
  in
  let respond ?(headers = []) status = Ok { Response.status; headers; body = "" } in
  let sleep span =
    printf "sleep %s\n" (Time_ns.Span.to_string_hum span);
    return ()
  in
  let log sexp = print_s sexp in
  let request idempotent =
    { Request.meth = `POST
    ; uri = Uri.of_string "https://example.test/grid/quotes"
    ; headers = [ "Authorization", "Basic xyz" ]
    ; body = None
    ; idempotent
    }
  in
  let run idempotent steps =
    script := steps;
    let%map result = Retry.run ~sleep ~log transport (request idempotent) in
    print_s
      [%sexp
        (Result.map result ~f:(fun (r : Response.t) -> r.status) : (int, string) Result.t)]
  in
  let%bind () =
    run
      true
      [ respond 503
      ; respond 429 ~headers:[ "Retry-After", "2"; "x-request-id", "r-1" ]
      ; Error "connection reset"
      ; respond 200
      ]
  in
  [%expect
    {|
    ("lightspark retry" (meth POST) (uri /grid/quotes) (why "503 request_id=-")
     (attempt 1) (wait 250ms))
    sleep 250ms
    ("lightspark retry" (meth POST) (uri /grid/quotes) (why "429 request_id=r-1")
     (attempt 2) (wait 2s))
    sleep 2s
    ("lightspark retry" (meth POST) (uri /grid/quotes) (why "connection reset")
     (attempt 3) (wait 1s))
    sleep 1s
    (Ok 200)
    |}];
  (* A non-idempotent write is resent only on 429. *)
  let%bind () = run false [ respond 502 ] in
  [%expect {| (Ok 502) |}];
  let%bind () = run false [ respond 429; respond 201 ] in
  [%expect
    {|
    ("lightspark retry" (meth POST) (uri /grid/quotes) (why "429 request_id=-")
     (attempt 1) (wait 250ms))
    sleep 250ms
    (Ok 201)
    |}];
  print_s [%sexp (request true : Request.t)];
  [%expect
    {|
    ((meth POST) (uri https://example.test/grid/quotes)
     (headers ((Authorization <redacted>))) (idempotent true))
    |}];
  return ()
;;
