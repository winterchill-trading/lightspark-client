(** Webhook signature verification for both APIs. Always verify the raw request body,
    before parsing it. *)

open! Core

module Lightspark : sig
  (** [lightspark-signature]: lowercase hex HMAC-SHA256 of the body, keyed with the
      webhook secret from the API configuration. *)
  val signature_header : string

  type event =
    { event_type : string (** [PAYMENT_FINISHED], [NODE_STATUS], [WALLET_STATUS], ... *)
    ; event_id : string
    ; timestamp : string
    ; entity_id : string
    ; wallet_id : string option
    }
  [@@deriving sexp, compare, equal]

  val sign : secret:string -> body:string -> string
  val verify : secret:string -> body:string -> signature:string -> event Or_error.t
end

module Grid : sig
  (** [X-Grid-Signature]: base64 DER ECDSA P-256/SHA-256 signature of the body, either
      bare or wrapped as [{"v":"1","s":"<base64>"}]. *)
  val signature_header : string

  type event =
    { id : string (** delivery id; use it to de-duplicate *)
    ; type_ : string (** [OBJECT.EVENT], e.g. [OUTGOING_PAYMENT.COMPLETED] *)
    ; timestamp : string
    ; data : string (** the [data] object as compact JSON *)
    }
  [@@deriving sexp, compare, equal]

  val verify
    :  public_key:P256.public_key
    -> body:string
    -> signature:string
    -> event Or_error.t
end
