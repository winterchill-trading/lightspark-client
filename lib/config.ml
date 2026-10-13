open! Core

module Mode = struct
  type t =
    | Sandbox
    | Live
  [@@deriving sexp, compare, equal]
end

type t =
  { client_id : string
  ; client_secret : string
  ; graphql_url : Uri.t
  ; grid_url : Uri.t
  ; mode : Mode.t
  }

let sexp_of_t t =
  let client_id =
    if String.length t.client_id <= 4
    then "<redacted>"
    else String.prefix t.client_id 4 ^ "..."
  in
  [%sexp
    { client_id : string
    ; client_secret = "<redacted>"
    ; graphql_url = (Uri.to_string t.graphql_url : string)
    ; grid_url = (Uri.to_string t.grid_url : string)
    ; mode = (t.mode : Mode.t)
    }]
;;

let default_graphql_url =
  Uri.of_string "https://api.lightspark.com/graphql/server/2023-09-13"
;;

let default_grid_url = Uri.of_string "https://api.lightspark.com/grid/2025-10-13"

let create
  ?(graphql_url = default_graphql_url)
  ?(grid_url = default_grid_url)
  ?(live = false)
  ~client_id
  ~client_secret
  ()
  =
  { client_id
  ; client_secret
  ; graphql_url
  ; grid_url
  ; mode = (if live then Live else Sandbox)
  }
;;

let client_id_var = "LIGHTSPARK_CLIENT_ID"
let client_secret_var = "LIGHTSPARK_CLIENT_SECRET"
let graphql_url_var = "LIGHTSPARK_GRAPHQL_URL"
let grid_url_var = "LIGHTSPARK_GRID_URL"

let of_env ?(getenv = Sys.getenv) ?live () =
  let get name =
    match getenv name with
    | None -> None
    | Some v ->
      (match String.strip v with
       | "" -> None
       | v -> Some v)
  in
  let required name =
    match get name with
    | Some v -> Ok v
    | None -> Or_error.error_s [%message "environment variable not set" (name : string)]
  in
  let open Or_error.Let_syntax in
  let%map client_id = required client_id_var
  and client_secret = required client_secret_var in
  create
    ?graphql_url:(Option.map (get graphql_url_var) ~f:Uri.of_string)
    ?grid_url:(Option.map (get grid_url_var) ~f:Uri.of_string)
    ?live
    ~client_id
    ~client_secret
    ()
;;

let is_live t = Mode.equal t.mode Live

let%expect_test "of_env redacts and defaults to sandbox" =
  let env =
    String.Map.of_alist_exn
      [ client_id_var, "abcdef0123"; client_secret_var, "s3cr3t"; grid_url_var, "" ]
  in
  let t = of_env ~getenv:(Map.find env) () |> Or_error.ok_exn in
  print_s [%sexp (t : t)];
  [%expect
    {|
    ((client_id abcd...) (client_secret <redacted>)
     (graphql_url https://api.lightspark.com/graphql/server/2023-09-13)
     (grid_url https://api.lightspark.com/grid/2025-10-13) (mode Sandbox))
    |}];
  print_s [%sexp (of_env ~getenv:(fun _ -> None) () : t Or_error.t)];
  [%expect
    {|
    (Error
     (("environment variable not set" (name LIGHTSPARK_CLIENT_ID))
      ("environment variable not set" (name LIGHTSPARK_CLIENT_SECRET))))
    |}]
;;
