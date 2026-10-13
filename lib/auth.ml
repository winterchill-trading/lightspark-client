open! Core

let token (config : Config.t) =
  Base64.encode_string (config.client_id ^ ":" ^ config.client_secret)
;;

let header config = "Authorization", "Basic " ^ token config
let redacted = "<redacted>"

let redact (config : Config.t) s =
  List.fold
    [ token config; config.client_secret; config.client_id ]
    ~init:s
    ~f:(fun s secret ->
      if String.is_empty secret
      then s
      else String.substr_replace_all s ~pattern:secret ~with_:redacted)
;;

let is_sensitive name =
  let name = String.lowercase name in
  String.equal name "authorization"
  || ((not (String.is_prefix name ~prefix:"idempotency"))
      && List.exists
           [ "key"; "secret"; "token"; "signature"; "signing"; "cookie" ]
           ~f:(fun s -> String.is_substring name ~substring:s))
;;

let redact_headers headers =
  List.map headers ~f:(fun (k, v) -> if is_sensitive k then k, redacted else k, v)
;;

let%expect_test "header and redaction" =
  let config = Config.create ~client_id:"id123456" ~client_secret:"secret789" () in
  let name, value = header config in
  print_endline (name ^ ": " ^ value);
  [%expect {| Authorization: Basic aWQxMjM0NTY6c2VjcmV0Nzg5 |}];
  print_endline (redact config ("error from id123456 using secret789 and " ^ value));
  [%expect {| error from <redacted> using <redacted> and Basic <redacted> |}];
  print_s
    [%sexp
      (redact_headers
         [ "Authorization", "Basic x"; "Idempotency-Key", "k"; "Accept", "json" ]
       : (string * string) list)];
  [%expect {| ((Authorization <redacted>) (Idempotency-Key k) (Accept json)) |}]
;;
