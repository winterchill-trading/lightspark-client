(** Grid REST API client.

    Reads need nothing special. Writes that can move money (customers, quotes, quote
    execution) are refused unless the config is [Live] or [GET /config] says the platform
    is a sandbox (see {!Grid_types.Platform_config.looks_like_sandbox}). [/sandbox/*]
    endpoints are sandbox-only on the server side. *)

open! Core
open! Async
open Grid_types

type t
type 'a response := 'a Api_error.result Deferred.t

val create
  :  ?transport:Transport.t
  -> ?policy:Transport.Retry.policy
  -> ?log:(Sexp.t -> unit)
  -> Config.t
  -> t

(** Turns a response into a value or an error; exposed for fixture tests. *)
val decode_response
  :  ?redact:(string -> string)
  -> what:string
  -> (Yojson.Safe.t -> 'a)
  -> Transport.Response.t
  -> 'a Api_error.result

(** {2 Reads} *)

val platform_config : t -> Platform_config.t response

val customers
  :  ?limit:int
  -> ?cursor:string
  -> ?platform_customer_id:string
  -> t
  -> Customer.t Page.t response

val customer : t -> id:string -> Customer.t response

val customer_internal_accounts
  :  ?limit:int
  -> ?cursor:string
  -> ?customer_id:string
  -> ?currency:string
  -> t
  -> Internal_account.t Page.t response

val platform_internal_accounts : t -> Internal_account.t Page.t response
val internal_account : t -> id:string -> Internal_account.t response

val transactions
  :  ?limit:int
  -> ?cursor:string
  -> ?customer_id:string
  -> ?status:string
  -> ?type_:string
  -> t
  -> Transaction.t Page.t response

val transaction : t -> id:string -> Transaction.t response

val exchange_rates
  :  ?source_currency:string
  -> ?destination_currency:string
  -> ?sending_amount:int
  -> t
  -> Exchange_rate.t list response

val quote : t -> id:string -> Quote.t response

(** Follows [nextCursor] until [hasMore] is false or [max_pages] pages were read. *)
val all_pages
  :  ?max_pages:int
  -> (cursor:string option -> 'a Page.t response)
  -> 'a list response

(** {2 Writes} *)

(** Refuses unless [Live] or the platform looks like a sandbox. The answer is cached. *)
val ensure_sandbox_or_live : t -> unit response

(** Creates an individual customer. [idempotency_key] makes retries safe. *)
val create_individual_customer
  :  ?region:string
  -> ?currencies:string list
  -> ?email:string
  -> t
  -> platform_customer_id:string
  -> full_name:string
  -> birth_date:string
  -> nationality:string
  -> idempotency_key:string
  -> Customer.t response

(** [POST /sandbox/internal-accounts/{id}/fund]; sandbox keys only. *)
val sandbox_fund_internal_account
  :  ?description:string
  -> t
  -> account_id:string
  -> amount:int
  -> Internal_account.t response

module Destination : sig
  type t =
    | Account of string
    | Uma_address of
        { address : string
        ; currency : string
        }
end

val create_quote
  :  ?immediately_execute:bool
  -> ?description:string
  -> t
  -> source_account_id:string
  -> destination:Destination.t
  -> locked_side:[ `Sending | `Receiving ]
  -> amount:int
  -> idempotency_key:string
  -> Quote.t response

val execute_quote : t -> quote_id:string -> idempotency_key:string -> Quote.t response
