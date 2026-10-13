open! Core
open! Async
module Transport = Lightspark_client.Transport

let get transport url =
  transport
    { Transport.Request.meth = `GET
    ; uri = Uri.of_string url
    ; headers = []
    ; body = None
    ; idempotent = true
    }
;;

(* A certificate failure surfaces either as an OpenSSL handshake error or as conduit's
   "Connection verification failed." from our host check. *)
let is_certificate_error message =
  List.exists
    [ "certificate"; "verif"; "self signed"; "self-signed"; "expired" ]
    ~f:(fun s -> String.is_substring (String.lowercase message) ~substring:s)
;;

let is_unreachable message =
  List.exists
    [ "timeout"
    ; "unix_getaddrinfo"
    ; "getaddrinfo"
    ; "unreachable"
    ; "connection refused"
    ; "no address"
    ; "name or service"
    ; "nodename"
    ]
    ~f:(fun s -> String.is_substring (String.lowercase message) ~substring:s)
;;

let main () =
  let transport = Transport.cohttp ~timeout:(Time_ns.Span.of_int_sec 15) () in
  let failures = ref 0 in
  let%bind () =
    Deferred.List.iter
      ~how:`Sequential
      [ "https://expired.badssl.com/"
      ; "https://self-signed.badssl.com/"
      ; "https://wrong.host.badssl.com/"
      ]
      ~f:(fun url ->
        match%map get transport url with
        | Ok response ->
          incr failures;
          printf "FAIL %s: accepted (status %d)\n" url response.status
        | Error message when is_certificate_error message ->
          printf "ok   %s: rejected (%s)\n" url message
        | Error message when is_unreachable message ->
          printf "skip %s: unreachable (%s)\n" url message
        | Error message ->
          incr failures;
          printf "FAIL %s: unexpected error %s\n" url message)
  in
  (* A good certificate must still work, or the checks above prove nothing. *)
  let%bind () =
    match%map get transport "https://api.lightspark.com/grid/2025-10-13/config" with
    | Ok response -> printf "ok   api.lightspark.com: status %d\n" response.status
    | Error message when is_unreachable message ->
      printf "skip api.lightspark.com: unreachable (%s)\n" message
    | Error message ->
      incr failures;
      printf "FAIL api.lightspark.com: %s\n" message
  in
  if !failures > 0 then exit 1 else return ()
;;

let () =
  Command.async ~summary:"TLS verification check" (Command.Param.return main)
  |> Command_unix.run
;;
