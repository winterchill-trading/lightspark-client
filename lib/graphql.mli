(** Transport for the GraphQL server API: one document plus variables in, the [data]
    object or a structured error out. *)

open! Core
open! Async

type t

val create
  :  ?transport:Transport.t
  -> ?policy:Transport.Retry.policy
  -> ?log:(Sexp.t -> unit)
  -> Config.t
  -> t

val config : t -> Config.t

(** The name after [query] or [mutation] at the start of a document. *)
val operation_name : string -> string option

val is_mutation : string -> bool

(** Request body, as the official SDKs send it. *)
val request_body : query:string -> variables:(string * Yojson.Safe.t) list -> string

(** Turns an HTTP status and body into [data] or an error. GraphQL [errors] win over the
    status (the server answers 401 with a GraphQL body); 429 becomes [Rate_limited].
    Bodies in errors are passed through [redact]. *)
val decode_response
  :  ?redact:(string -> string)
  -> Transport.Response.t
  -> Yojson.Safe.t Api_error.result

(** Queries are resent on 5xx and timeouts; mutations only on 429. *)
val execute
  :  t
  -> query:string
  -> variables:(string * Yojson.Safe.t) list
  -> Yojson.Safe.t Api_error.result Deferred.t
