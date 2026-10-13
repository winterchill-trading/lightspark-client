(** Errors from either API, structured enough to branch on. *)

open! Core

module Graphql_error : sig
  type t =
    { message : string
    ; path : string list
    ; error_name : string option
    (** [extensions.error_name], e.g. [AuthenticationException] *)
    }
  [@@deriving sexp, compare, equal]

  val of_json : Yojson.Safe.t -> t
end

type t =
  | Http of
      { status : int
      ; code : string option (** Grid [code], e.g. [INVALID_INPUT] *)
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
  (** The client refused to send a request, e.g. a write outside sandbox without
      [~live:true]. *)
[@@deriving sexp_of]

val to_error : t -> Error.t

type 'a result = ('a, t) Result.t

val ok_exn : 'a result -> 'a
