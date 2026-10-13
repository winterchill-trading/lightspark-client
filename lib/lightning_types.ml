open! Core
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Currency_amount = struct
  type t =
    { original_value : int [@key "currency_amount_original_value"]
    ; original_unit : string [@key "currency_amount_original_unit"]
    ; preferred_currency_unit : string [@key "currency_amount_preferred_currency_unit"]
    ; preferred_currency_value_rounded : int
         [@key "currency_amount_preferred_currency_value_rounded"]
    ; preferred_currency_value_approx : float
         [@key "currency_amount_preferred_currency_value_approx"]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Account = struct
  type t =
    { id : string [@key "account_id"]
    ; created_at : string [@key "account_created_at"]
    ; updated_at : string [@key "account_updated_at"]
    ; name : string option [@key "account_name"] [@default None]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Page_info = struct
  type t =
    { has_next_page : bool [@key "page_info_has_next_page"]
    ; end_cursor : string option [@key "page_info_end_cursor"] [@default None]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Balances = struct
  type t =
    { owned : Currency_amount.t [@key "balances_owned_balance"]
    ; available_to_send : Currency_amount.t [@key "balances_available_to_send_balance"]
    ; available_to_withdraw : Currency_amount.t
         [@key "balances_available_to_withdraw_balance"]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Node = struct
  type t =
    { typename : string [@key "__typename"]
    ; id : string [@key "lightspark_node_id"]
    ; created_at : string [@key "lightspark_node_created_at"]
    ; display_name : string [@key "lightspark_node_display_name"]
    ; bitcoin_network : string [@key "lightspark_node_bitcoin_network"]
    ; public_key : string option [@key "lightspark_node_public_key"] [@default None]
    ; status : string option [@key "lightspark_node_status"] [@default None]
    ; balances : Balances.t option [@key "lightspark_node_balances"] [@default None]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Wallet = struct
  type t =
    { id : string [@key "wallet_id"]
    ; created_at : string [@key "wallet_created_at"]
    ; updated_at : string [@key "wallet_updated_at"]
    ; last_login_at : string option [@key "wallet_last_login_at"] [@default None]
    ; balances : Balances.t option [@key "wallet_balances"] [@default None]
    ; third_party_identifier : string [@key "wallet_third_party_identifier"]
    ; status : string [@key "wallet_status"]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Transaction = struct
  type t =
    { typename : string [@key "__typename"]
    ; id : string [@key "transaction_id"]
    ; created_at : string [@key "transaction_created_at"]
    ; updated_at : string [@key "transaction_updated_at"]
    ; status : string [@key "transaction_status"]
    ; resolved_at : string option [@key "transaction_resolved_at"] [@default None]
    ; amount : Currency_amount.t [@key "transaction_amount"]
    ; transaction_hash : string option
         [@key "transaction_transaction_hash"] [@default None]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Invoice_data = struct
  type t =
    { encoded_payment_request : string [@key "invoice_data_encoded_payment_request"]
    ; bitcoin_network : string [@key "invoice_data_bitcoin_network"]
    ; payment_hash : string [@key "invoice_data_payment_hash"]
    ; amount : Currency_amount.t [@key "invoice_data_amount"]
    ; created_at : string [@key "invoice_data_created_at"]
    ; expires_at : string [@key "invoice_data_expires_at"]
    ; memo : string option [@key "invoice_data_memo"] [@default None]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Invoice = struct
  type t =
    { id : string [@key "invoice_id"]
    ; created_at : string [@key "invoice_created_at"]
    ; updated_at : string [@key "invoice_updated_at"]
    ; data : Invoice_data.t [@key "invoice_data"]
    ; status : string [@key "invoice_status"]
    ; amount_paid : Currency_amount.t option [@key "invoice_amount_paid"] [@default None]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Connection = struct
  type 'a t =
    { count : int
    ; page_info : Page_info.t
    ; entities : 'a list
    }
  [@@deriving sexp, compare, equal]

  let of_json ~prefix entity_of_json json =
    let field name = Yojson.Safe.Util.member (prefix ^ "_" ^ name) json in
    { count = Yojson.Safe.Util.to_int (field "count")
    ; page_info = Page_info.t_of_yojson (field "page_info")
    ; entities = List.map (Yojson.Safe.Util.to_list (field "entities")) ~f:entity_of_json
    }
  ;;
end
