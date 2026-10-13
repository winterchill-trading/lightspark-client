open! Core
open! Async

type t =
  { config : Config.t
  ; transport : Transport.t
  ; policy : Transport.Retry.policy
  ; log : Sexp.t -> unit
  }

let create
  ?(transport = Transport.cohttp ())
  ?(policy = Transport.Retry.default)
  ?(log = fun sexp -> Log.Global.debug_s sexp)
  config
  =
  { config; transport; policy; log }
;;

let config t = t.config

let words document =
  String.split_on_chars document ~on:[ ' '; '\n'; '\t'; '\r'; '('; '{' ]
  |> List.filter ~f:(Fn.non String.is_empty)
;;

let operation_name document =
  match words document with
  | ("query" | "mutation") :: name :: _ -> Some name
  | _ -> None
;;

let is_mutation document =
  match words document with
  | "mutation" :: _ -> true
  | _ -> false
;;

let request_body ~query ~variables =
  Yojson.Safe.to_string
    (`Assoc
      [ ( "operationName"
        , match operation_name query with
          | Some name -> `String name
          | None -> `Null )
      ; "query", `String query
      ; "variables", `Assoc variables
      ])
;;

let decode_response ?(redact = Fn.id) (response : Transport.Response.t) =
  let request_id = Transport.Response.request_id response in
  let http_error () =
    Error
      (Api_error.Http
         { status = response.status
         ; code = None
         ; reason = None
         ; request_id
         ; body = redact response.body
         })
  in
  match Yojson.Safe.from_string response.body with
  | exception _ ->
    if response.status = 429
    then
      Error
        (Api_error.Rate_limited
           { retry_after = Transport.Response.retry_after response; request_id })
    else if response.status >= 200 && response.status < 300
    then
      Error
        (Api_error.Decode
           { what = "graphql response"
           ; message = "invalid JSON: " ^ redact response.body
           })
    else http_error ()
  | `Assoc fields ->
    let find name = List.Assoc.find fields name ~equal:String.equal in
    (match find "errors", find "data" with
     | Some (`List (_ :: _ as errors)), _ ->
       Error
         (Api_error.Graphql
            { status = response.status
            ; errors = List.map errors ~f:Api_error.Graphql_error.of_json
            ; request_id
            })
     | _ when response.status = 429 ->
       Error
         (Api_error.Rate_limited
            { retry_after = Transport.Response.retry_after response; request_id })
     | _ when response.status < 200 || response.status >= 300 -> http_error ()
     | _, Some (`Assoc _ as data) -> Ok data
     | _ ->
       Error
         (Api_error.Decode
            { what = "graphql response"; message = "no data: " ^ redact response.body }))
  | _ -> http_error ()
;;

let execute t ~query ~variables =
  let operation = operation_name query in
  let headers =
    [ Auth.header t.config
    ; "Content-Type", "application/json"
    ; "Accept", "application/json"
    ; "User-Agent", "lightspark-client-ocaml/0.1"
    ]
    @ Option.to_list (Option.map operation ~f:(fun op -> "X-GraphQL-Operation", op))
  in
  let request =
    { Transport.Request.meth = `POST
    ; uri = t.config.graphql_url
    ; headers
    ; body = Some (request_body ~query ~variables)
    ; idempotent = not (is_mutation query)
    }
  in
  match%map Transport.Retry.run ~policy:t.policy ~log:t.log t.transport request with
  | Error message -> Error (Api_error.Transport (Auth.redact t.config message))
  | Ok response ->
    t.log
      [%message
        "lightspark graphql"
          ~operation:(Option.value operation ~default:"-" : string)
          ~status:(response.status : int)
          ~request_id:
            (Option.value (Transport.Response.request_id response) ~default:"-" : string)];
    decode_response ~redact:(Auth.redact t.config) response
;;

let%expect_test "operation names and bodies" =
  let q = "\nquery GetCurrentAccount {\n current_account { id } }" in
  print_s [%sexp (operation_name q : string option), (is_mutation q : bool)];
  print_s
    [%sexp (operation_name "mutation CreateInvoice($node_id: ID!) { x }" : string option)];
  print_endline (request_body ~query:"query A { b }" ~variables:[ "first", `Int 2 ]);
  [%expect
    {|
    ((GetCurrentAccount) false)
    (CreateInvoice)
    {"operationName":"A","query":"query A { b }","variables":{"first":2}}
    |}];
  return ()
;;

let%expect_test "decoding" =
  let decode ?(headers = []) status body =
    print_s
      [%sexp
        (decode_response { Transport.Response.status; headers; body }
         |> Result.map ~f:Yojson.Safe.to_string
         : string Api_error.result)]
  in
  (* Recorded from the live server for a token of the wrong kind. *)
  decode
    401
    ~headers:[ "x-request-id", "req-1" ]
    {|{"data": {"current_account": null}, "errors": [{"message": "Not logged in.", "locations": [{"line": 1, "column": 27}], "path": ["current_account"], "extensions": {"error_name": "AuthenticationException"}}]}|};
  decode 200 {|{"data": {"current_account": {"id": "Account:1"}}}|};
  decode 429 ~headers:[ "Retry-After", "3" ] "slow down";
  decode 502 "<html>bad gateway</html>";
  decode 200 {|{"data": null}|};
  [%expect
    {|
    (Error
     (Graphql (status 401)
      (errors
       (((message "Not logged in.") (path (current_account))
         (error_name (AuthenticationException)))))
      (request_id (req-1))))
    (Ok "{\"current_account\":{\"id\":\"Account:1\"}}")
    (Error (Rate_limited (retry_after (3s)) (request_id ())))
    (Error
     (Http (status 502) (code ()) (reason ()) (request_id ())
      (body "<html>bad gateway</html>")))
    (Error
     (Decode (what "graphql response") (message "no data: {\"data\": null}")))
    |}];
  return ()
;;
