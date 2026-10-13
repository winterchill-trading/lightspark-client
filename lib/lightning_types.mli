(** Decoded GraphQL objects. Field names drop the SDK alias prefixes; enum-like values
    (units, networks, statuses) stay strings so new server values do not break decoding. *)

open! Core

module Currency_amount : sig
  type t =
    { original_value : int
    ; original_unit : string (** [SATOSHI], [MILLISATOSHI], [USD], ... *)
    ; preferred_currency_unit : string
    ; preferred_currency_value_rounded : int
    ; preferred_currency_value_approx : float
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Account : sig
  type t =
    { id : string
    ; created_at : string
    ; updated_at : string
    ; name : string option
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Page_info : sig
  type t =
    { has_next_page : bool
    ; end_cursor : string option
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Balances : sig
  type t =
    { owned : Currency_amount.t
    ; available_to_send : Currency_amount.t
    ; available_to_withdraw : Currency_amount.t
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Node : sig
  type t =
    { typename : string
    (** [LightsparkNodeWithOSK] or [LightsparkNodeWithRemoteSigning] *)
    ; id : string
    ; created_at : string
    ; display_name : string
    ; bitcoin_network : string (** [MAINNET], [REGTEST], ... *)
    ; public_key : string option
    ; status : string option
    ; balances : Balances.t option
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Wallet : sig
  type t =
    { id : string
    ; created_at : string
    ; updated_at : string
    ; last_login_at : string option
    ; balances : Balances.t option
    ; third_party_identifier : string
    ; status : string
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Transaction : sig
  type t =
    { typename : string (** [IncomingPayment], [OutgoingPayment], [Deposit], ... *)
    ; id : string
    ; created_at : string
    ; updated_at : string
    ; status : string (** [SUCCESS], [FAILED], [PENDING], [NOT_STARTED], ... *)
    ; resolved_at : string option
    ; amount : Currency_amount.t
    ; transaction_hash : string option
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Invoice_data : sig
  type t =
    { encoded_payment_request : string
    ; bitcoin_network : string
    ; payment_hash : string
    ; amount : Currency_amount.t
    ; created_at : string
    ; expires_at : string
    ; memo : string option
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Invoice : sig
  type t =
    { id : string
    ; created_at : string
    ; updated_at : string
    ; data : Invoice_data.t
    ; status : string (** [OPEN], [SUCCEEDED], [FAILED], ... *)
    ; amount_paid : Currency_amount.t option
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Connection : sig
  type 'a t =
    { count : int
    ; page_info : Page_info.t
    ; entities : 'a list
    }
  [@@deriving sexp, compare, equal]

  (** Decodes [<prefix>_count], [<prefix>_page_info] and [<prefix>_entities], the SDK's
      connection aliases (e.g. prefix [account_to_nodes_connection]). *)
  val of_json : prefix:string -> (Yojson.Safe.t -> 'a) -> Yojson.Safe.t -> 'a t
end
