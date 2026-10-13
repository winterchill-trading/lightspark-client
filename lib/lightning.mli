(** Typed operations on the GraphQL server API.

    Writes are guarded: unless the config is [Live], the node must be on [REGTEST] (test
    mode), checked with a read before the mutation is sent. *)

open! Core
open! Async
open Lightning_types

type 'a response := 'a Api_error.result Deferred.t

val current_account : Graphql.t -> Account.t response

val nodes
  :  ?first:int
  -> ?after:string
  -> ?bitcoin_networks:string list
  -> Graphql.t
  -> Node.t Connection.t response

val wallets : ?first:int -> ?after:string -> Graphql.t -> Wallet.t Connection.t response

val transactions
  :  ?first:int
  -> ?after:string
  -> ?bitcoin_network:string
  -> ?node_id:string
  -> Graphql.t
  -> Transaction.t Connection.t response

val invoice_for_payment_hash : Graphql.t -> payment_hash:string -> Invoice.t response

val decode_payment_request
  :  Graphql.t
  -> encoded_payment_request:string
  -> Invoice_data.t response

(** [None] when the id is not a Lightspark node. *)
val node_network : Graphql.t -> node_id:string -> string option response

(** {2 Writes} *)

val create_invoice
  :  ?memo:string
  -> ?expiry_secs:int
  -> Graphql.t
  -> node_id:string
  -> amount_msats:int
  -> Invoice.t response

(** An invoice that a REGTEST node can pay; returns the encoded payment request. *)
val create_test_mode_invoice
  :  ?memo:string
  -> Graphql.t
  -> node_id:string
  -> amount_msats:int
  -> string response

(** Simulates paying one of our REGTEST invoices from outside. *)
val create_test_mode_payment
  :  ?amount_msats:int
  -> Graphql.t
  -> node_id:string
  -> encoded_invoice:string
  -> Transaction.t response

(** Adds test funds to a REGTEST node; returns the amount added. *)
val fund_node
  :  ?amount_sats:int
  -> Graphql.t
  -> node_id:string
  -> Currency_amount.t response

(** Pays an invoice from a remote-signing node. Nodes with an OSK need a signed request
    ([X-Lightspark-Signing]), which this client does not implement. *)
val pay_invoice
  :  ?amount_msats:int
  -> ?idempotency_key:string
  -> Graphql.t
  -> node_id:string
  -> encoded_invoice:string
  -> timeout_secs:int
  -> maximum_fees_msats:int
  -> Transaction.t response

(** {2 Decoders, exposed for fixture tests} *)

module Decode : sig
  val current_account : Yojson.Safe.t -> Account.t Api_error.result
  val nodes : Yojson.Safe.t -> Node.t Connection.t Api_error.result
  val wallets : Yojson.Safe.t -> Wallet.t Connection.t Api_error.result
  val transactions : Yojson.Safe.t -> Transaction.t Connection.t Api_error.result
  val invoice_for_payment_hash : Yojson.Safe.t -> Invoice.t Api_error.result
  val create_invoice : Yojson.Safe.t -> Invoice.t Api_error.result
  val create_test_mode_invoice : Yojson.Safe.t -> string Api_error.result
  val fund_node : Yojson.Safe.t -> Currency_amount.t Api_error.result
  val pay_invoice : Yojson.Safe.t -> Transaction.t Api_error.result
end
