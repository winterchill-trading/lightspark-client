(** HTTP Basic credentials and redaction of anything that could leak them. *)

open! Core

(** [Authorization: Basic base64(client_id:client_secret)]. *)
val header : Config.t -> string * string

(** Replaces every occurrence of the client id, the client secret and the encoded Basic
    token in [s] with [<redacted>]. Use it on anything that reaches a log or an error. *)
val redact : Config.t -> string -> string

(** Header list with the values of sensitive headers ([authorization], anything with
    [key], [secret], [token], [signature], [cookie] in its name) replaced. *)
val redact_headers : (string * string) list -> (string * string) list
