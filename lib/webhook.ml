open! Core

let member name = function
  | `Assoc fields -> List.Assoc.find fields name ~equal:String.equal
  | _ -> None
;;

let string_field json name =
  match member name json with
  | Some (`String s) -> Ok s
  | _ -> Or_error.error_s [%message "webhook body: missing string field" (name : string)]
;;

let parse_json body =
  match Yojson.Safe.from_string body with
  | json -> Ok json
  | exception _ -> Or_error.error_string "webhook body is not JSON"
;;

(* Equal-time comparison so a forged signature cannot be found byte by byte. *)
let constant_time_equal a b =
  String.length a = String.length b
  &&
  let diff = ref 0 in
  String.iteri a ~f:(fun i c -> diff := !diff lor (Char.to_int c lxor Char.to_int b.[i]));
  !diff = 0
;;

module Lightspark = struct
  let signature_header = "lightspark-signature"

  type event =
    { event_type : string
    ; event_id : string
    ; timestamp : string
    ; entity_id : string
    ; wallet_id : string option
    }
  [@@deriving sexp, compare, equal]

  let sign ~secret ~body =
    Cryptokit.hash_string (Cryptokit.MAC.hmac_sha256 secret) body
    |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
  ;;

  let verify ~secret ~body ~signature =
    let open Or_error.Let_syntax in
    let expected = sign ~secret ~body in
    if not (constant_time_equal expected (String.lowercase (String.strip signature)))
    then Or_error.error_string "lightspark webhook signature mismatch"
    else (
      let%bind json = parse_json body in
      let%map event_type = string_field json "event_type"
      and event_id = string_field json "event_id"
      and timestamp = string_field json "timestamp"
      and entity_id = string_field json "entity_id" in
      let wallet_id = Result.ok (string_field json "wallet_id") in
      { event_type; event_id; timestamp; entity_id; wallet_id })
  ;;

  let%expect_test _ =
    let secret = "test-webhook-secret" in
    let body =
      {|{"event_type": "PAYMENT_FINISHED", "event_id": "1615c8be5aa44e429eba700db2ed8ca5", "timestamp": "2023-05-17T23:56:47.874449+00:00", "entity_id": "lightning_transaction:01882c25-157a-f96b-0000-362d42b64397"}|}
    in
    let signature = sign ~secret ~body in
    print_s [%sexp (verify ~secret ~body ~signature : event Or_error.t)];
    print_s
      [%sexp
        (Result.is_ok (verify ~secret ~body:(body ^ " ") ~signature) : bool)
        , (Result.is_ok (verify ~secret:"other" ~body ~signature) : bool)
        , (Result.is_ok (verify ~secret ~body ~signature:"00") : bool)];
    [%expect
      {|
      (Ok
       ((event_type PAYMENT_FINISHED) (event_id 1615c8be5aa44e429eba700db2ed8ca5)
        (timestamp 2023-05-17T23:56:47.874449+00:00)
        (entity_id lightning_transaction:01882c25-157a-f96b-0000-362d42b64397)
        (wallet_id ())))
      (false false false)
      |}]
  ;;
end

module Grid = struct
  let signature_header = "X-Grid-Signature"

  type event =
    { id : string
    ; type_ : string
    ; timestamp : string
    ; data : string
    }
  [@@deriving sexp, compare, equal]

  let signature_bytes header =
    let header = String.strip header in
    let b64 =
      match Yojson.Safe.from_string header with
      | `Assoc _ as json ->
        (match member "s" json with
         | Some (`String s) -> s
         | _ -> header)
      | _ | (exception _) -> header
    in
    Base64.decode b64 |> Result.map_error ~f:(fun (`Msg m) -> Error.of_string m)
  ;;

  let verify ~public_key ~body ~signature =
    let open Or_error.Let_syntax in
    let%bind signature = signature_bytes signature in
    if not (P256.verify public_key ~message:body ~signature)
    then Or_error.error_string "grid webhook signature mismatch"
    else (
      let%bind json = parse_json body in
      let%map id = string_field json "id"
      and type_ = string_field json "type"
      and timestamp = string_field json "timestamp" in
      let data =
        Option.value_map (member "data" json) ~default:"null" ~f:Yojson.Safe.to_string
      in
      { id; type_; timestamp; data })
  ;;
end
