(** Grid API objects. Amounts are integers in the currency's smallest unit ([decimals]
    places). Enum-like fields stay strings so new server values decode. *)

open! Core

module Currency : sig
  type t =
    { code : string
    ; decimals : int
    ; name : string option
    ; symbol : string option
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Amount : sig
  type t =
    { amount : int
    ; currency : Currency.t
    }
  [@@deriving sexp, compare, equal, yojson]

  (** [12345] with 2 decimals prints as [123.45 USD]. *)
  val to_string_hum : t -> string
end

module Supported_currency : sig
  type t =
    { currency_code : string
    ; min_amount : int option
    ; max_amount : int option
    ; enabled_transaction_types : string list
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Platform_config : sig
  type t =
    { id : string
    ; uma_domain : string option
    ; proxy_uma_subdomain : string option
    ; is_regulated_financial_institution : bool option
    ; supported_currencies : Supported_currency.t list
    ; created_at : string
    ; updated_at : string
    }
  [@@deriving sexp, compare, equal, yojson]

  (** A sandbox platform's UMA domain and proxy subdomain contain [sandbox]. The API has
      no explicit flag, so this is the client's sandbox check before money-moving writes. *)
  val looks_like_sandbox : t -> bool
end

module Customer : sig
  type t =
    { id : string
    ; platform_customer_id : string option
    ; customer_type : string (** [INDIVIDUAL] or [BUSINESS] *)
    ; uma_address : string option
    ; kyc_status : string option
    ; full_name : string option
    ; email : string option
    ; is_deleted : bool option
    ; created_at : string
    ; updated_at : string
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Internal_account : sig
  type t =
    { id : string
    ; customer_id : string option
    ; type_ : string (** [INTERNAL_FIAT], [INTERNAL_CRYPTO], [EMBEDDED_WALLET], ... *)
    ; status : string
    ; balance : Amount.t
    ; created_at : string
    ; updated_at : string
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Transaction : sig
  type t =
    { id : string
    ; type_ : string (** [INCOMING], [OUTGOING], [CARD], ... *)
    ; status : string
    (** [CREATED], [PENDING], [PROCESSING], [COMPLETED], [FAILED], ... *)
    ; direction : string option
    ; customer_id : string option
    ; platform_customer_id : string option
    ; description : string option
    ; sent_amount : Amount.t option
    ; received_amount : Amount.t option
    ; quote_id : string option
    ; failure_reason : string option
    ; created_at : string
    ; updated_at : string option
    ; settled_at : string option
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Fees : sig
  type t =
    { fixed : int option
    ; total : int option
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Exchange_rate : sig
  type t =
    { source_currency : Currency.t
    ; destination_currency : Currency.t
    ; destination_payment_rail : string option
    ; exchange_rate : float
    ; fees : Fees.t option
    ; min_sending_amount : int option
    ; max_sending_amount : int option
    ; sending_amount : int option
    ; receiving_amount : int option
    ; updated_at : string option
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Quote : sig
  type t =
    { id : string
    ; status : string
    (** [PENDING], [PROCESSING], [COMPLETED], [FAILED], [EXPIRED], ... *)
    ; created_at : string
    ; expires_at : string
    ; sending_currency : Currency.t
    ; receiving_currency : Currency.t
    ; total_sending_amount : int
    ; total_receiving_amount : int
    ; exchange_rate : float
    ; fees_included : int
    ; transaction_id : string option
    }
  [@@deriving sexp, compare, equal, yojson]
end

module Page : sig
  type 'a t =
    { data : 'a list
    ; has_more : bool
    ; next_cursor : string option
    ; total_count : int option
    }
  [@@deriving sexp, compare, equal]

  val of_json : (Yojson.Safe.t -> 'a) -> Yojson.Safe.t -> 'a t
end

module Error_body : sig
  type t =
    { code : string
    ; reason : string option
    }
  [@@deriving sexp, compare, equal, yojson]
end
