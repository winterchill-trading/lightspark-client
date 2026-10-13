(** One HTTP exchange, and a retry loop around it.

    A transport only fails for network-level problems; every HTTP status is a
    [Response.t], so the API layers can decode error bodies. Tests swap the real transport
    for a function returning canned responses. *)

open! Core
open! Async

module Meth : sig
  type t =
    [ `GET
    | `POST
    | `PUT
    | `PATCH
    | `DELETE
    ]
  [@@deriving sexp_of, compare, equal]
end

module Request : sig
  type t =
    { meth : Meth.t
    ; uri : Uri.t
    ; headers : (string * string) list
    ; body : string option
    ; idempotent : bool
    (** Safe to resend after a timeout or a 5xx: reads, GraphQL queries, writes with an
        [Idempotency-Key]. *)
    }

  (** Redacted: sensitive header values are replaced. *)
  val sexp_of_t : t -> Sexp.t
end

module Response : sig
  type t =
    { status : int
    ; headers : (string * string) list
    ; body : string
    }
  [@@deriving sexp_of]

  (** Case-insensitive header lookup. *)
  val header : t -> string -> string option

  (** [x-request-id], which both APIs return on every response. *)
  val request_id : t -> string option

  (** [Retry-After] in seconds, when present. *)
  val retry_after : t -> Time_ns.Span.t option
end

type t = Request.t -> (Response.t, string) Result.t Deferred.t

(** cohttp-async with OpenSSL for [https]: the peer chain is verified against the system
    trust store and the certificate must name the host in the URI (SNI is sent too).
    [timeout] defaults to 30 s. *)
val cohttp : ?timeout:Time_ns.Span.t -> unit -> t

(** Wraps a transport so every response is written to [dir] as [<n>-<METHOD>-<path>.json]
    holding the status and the response body (never request headers or bodies). Fixtures
    for the tests are made this way, then redacted. [cohttp] applies it itself when
    [LIGHTSPARK_RECORD_DIR] is set. *)
val record : dir:string -> t -> t

module Retry : sig
  type policy =
    { max_attempts : int
    ; initial_backoff : Time_ns.Span.t
    ; max_backoff : Time_ns.Span.t
    }
  [@@deriving sexp_of]

  (** 4 attempts, 250 ms doubling up to 5 s. *)
  val default : policy

  val no_retry : policy

  (** 408, 425, 429, 500, 502, 503 and 504. *)
  val retryable_status : int -> bool

  (** Sends [request], resending on a retryable status or a transport failure. A 429 is
      always resent (the server did not process it); other failures only when
      [request.idempotent]. Waits [Retry-After] when the server gives one, else the
      exponential backoff. [log] sees one line per retry. *)
  val run
    :  ?policy:policy
    -> ?sleep:(Time_ns.Span.t -> unit Deferred.t)
    -> ?log:(Sexp.t -> unit)
    -> t
    -> Request.t
    -> (Response.t, string) Result.t Deferred.t
end
