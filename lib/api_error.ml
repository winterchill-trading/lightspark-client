open! Core

module Graphql_error = struct
  type t =
    { message : string
    ; path : string list
    ; error_name : string option
    }
  [@@deriving sexp, compare, equal]

  let of_json (json : Yojson.Safe.t) =
    let field name =
      match json with
      | `Assoc fields -> List.Assoc.find fields name ~equal:String.equal
      | _ -> None
    in
    let message =
      match field "message" with
      | Some (`String s) -> s
      | Some other -> Yojson.Safe.to_string other
      | None -> Yojson.Safe.to_string json
    in
    let path =
      match field "path" with
      | Some (`List items) ->
        List.map items ~f:(function
          | `String s -> s
          | `Int i -> Int.to_string i
          | other -> Yojson.Safe.to_string other)
      | _ -> []
    in
    let error_name =
      match field "extensions" with
      | Some (`Assoc ext) ->
        (match List.Assoc.find ext "error_name" ~equal:String.equal with
         | Some (`String s) -> Some s
         | _ -> None)
      | _ -> None
    in
    { message; path; error_name }
  ;;
end

type t =
  | Http of
      { status : int
      ; code : string option
      ; reason : string option
      ; request_id : string option
      ; body : string
      }
  | Graphql of
      { status : int
      ; errors : Graphql_error.t list
      ; request_id : string option
      }
  | Rate_limited of
      { retry_after : Time_ns.Span.t option
      ; request_id : string option
      }
  | Transport of string
  | Decode of
      { what : string
      ; message : string
      }
  | Refused of string
[@@deriving sexp_of]

let to_error t = Error.create_s [%sexp "lightspark", (t : t)]

type 'a result = ('a, t) Result.t [@@deriving sexp_of]

let ok_exn = function
  | Ok x -> x
  | Error t -> Error.raise (to_error t)
;;

let%expect_test "graphql error from the server" =
  let json =
    Yojson.Safe.from_string
      {|{"message": "Not logged in.", "locations": [{"line": 1, "column": 27}],
         "path": ["current_account"],
         "extensions": {"error_name": "AuthenticationException"}}|}
  in
  print_s [%sexp (Graphql_error.of_json json : Graphql_error.t)];
  [%expect
    {|
    ((message "Not logged in.") (path (current_account))
     (error_name (AuthenticationException)))
    |}]
;;
