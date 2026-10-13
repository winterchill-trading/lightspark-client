open! Core
open Lightspark_client

(** Contents of [fixtures/<path>]. *)
val read : string -> string

(** A [Transport.Response.t] with status 200 (or [status]) and the fixture as body. *)
val response : ?status:int -> string -> Transport.Response.t

(** A transport answering by request path suffix from [routes]; prints each request. *)
val fake_transport : (string * Transport.Response.t) list -> Transport.t
