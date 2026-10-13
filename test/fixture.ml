open! Core
open! Async
open Lightspark_client

let read path = In_channel.read_all ("fixtures/" ^ path)

let response ?(status = 200) path =
  { Transport.Response.status
  ; headers = [ "x-request-id", "req-fixture" ]
  ; body = read path
  }
;;

let fake_transport routes (request : Transport.Request.t) =
  let path = Uri.path request.uri in
  printf "%s %s\n" (Sexp.to_string [%sexp (request.meth : Transport.Meth.t)]) path;
  match List.find routes ~f:(fun (suffix, _) -> String.is_suffix path ~suffix) with
  | Some (_, response) -> return (Ok response)
  | None -> return (Error ("no fake route for " ^ path))
;;
