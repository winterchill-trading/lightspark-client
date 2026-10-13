open! Core
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Currency = struct
  type t =
    { code : string
    ; decimals : int
    ; name : string option [@default None]
    ; symbol : string option [@default None]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Amount = struct
  type t =
    { amount : int
    ; currency : Currency.t
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]

  let to_string_hum { amount; currency } =
    let decimals = currency.decimals in
    if decimals <= 0
    then sprintf "%d %s" amount currency.code
    else (
      let scale = Int.pow 10 decimals in
      let sign = if amount < 0 then "-" else "" in
      let a = Int.abs amount in
      sprintf "%s%d.%0*d %s" sign (a / scale) decimals (a mod scale) currency.code)
  ;;

  let%expect_test _ =
    let usd = { Currency.code = "USD"; decimals = 2; name = None; symbol = None } in
    List.iter [ 12345; 5; -250; 0 ] ~f:(fun amount ->
      print_endline (to_string_hum { amount; currency = usd }));
    print_endline
      (to_string_hum
         { amount = 1500; currency = { usd with code = "SAT"; decimals = 0 } });
    [%expect
      {|
      123.45 USD
      0.05 USD
      -2.50 USD
      0.00 USD
      1500 SAT
      |}]
  ;;
end

module Supported_currency = struct
  type t =
    { currency_code : string [@key "currencyCode"]
    ; min_amount : int option [@key "minAmount"] [@default None]
    ; max_amount : int option [@key "maxAmount"] [@default None]
    ; enabled_transaction_types : string list
         [@key "enabledTransactionTypes"] [@default []]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Platform_config = struct
  type t =
    { id : string
    ; uma_domain : string option [@key "umaDomain"] [@default None]
    ; proxy_uma_subdomain : string option [@key "proxyUmaSubdomain"] [@default None]
    ; is_regulated_financial_institution : bool option
         [@key "isRegulatedFinancialInstitution"] [@default None]
    ; supported_currencies : Supported_currency.t list
         [@key "supportedCurrencies"] [@default []]
    ; created_at : string [@key "createdAt"]
    ; updated_at : string [@key "updatedAt"]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]

  let looks_like_sandbox t =
    List.exists [ t.uma_domain; t.proxy_uma_subdomain ] ~f:(function
      | Some s -> String.is_substring (String.lowercase s) ~substring:"sandbox"
      | None -> false)
  ;;
end

module Customer = struct
  type t =
    { id : string
    ; platform_customer_id : string option [@key "platformCustomerId"] [@default None]
    ; customer_type : string [@key "customerType"]
    ; uma_address : string option [@key "umaAddress"] [@default None]
    ; kyc_status : string option [@key "kycStatus"] [@default None]
    ; full_name : string option [@key "fullName"] [@default None]
    ; email : string option [@default None]
    ; is_deleted : bool option [@key "isDeleted"] [@default None]
    ; created_at : string [@key "createdAt"]
    ; updated_at : string [@key "updatedAt"]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Internal_account = struct
  type t =
    { id : string
    ; customer_id : string option [@key "customerId"] [@default None]
    ; type_ : string [@key "type"]
    ; status : string
    ; balance : Amount.t
    ; created_at : string [@key "createdAt"]
    ; updated_at : string [@key "updatedAt"]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Transaction = struct
  type t =
    { id : string
    ; type_ : string [@key "type"]
    ; status : string
    ; direction : string option [@default None]
    ; customer_id : string option [@key "customerId"] [@default None]
    ; platform_customer_id : string option [@key "platformCustomerId"] [@default None]
    ; description : string option [@default None]
    ; sent_amount : Amount.t option [@key "sentAmount"] [@default None]
    ; received_amount : Amount.t option [@key "receivedAmount"] [@default None]
    ; quote_id : string option [@key "quoteId"] [@default None]
    ; failure_reason : string option [@key "failureReason"] [@default None]
    ; created_at : string [@key "createdAt"]
    ; updated_at : string option [@key "updatedAt"] [@default None]
    ; settled_at : string option [@key "settledAt"] [@default None]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Fees = struct
  type t =
    { fixed : int option [@default None]
    ; total : int option [@default None]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Exchange_rate = struct
  type t =
    { source_currency : Currency.t [@key "sourceCurrency"]
    ; destination_currency : Currency.t [@key "destinationCurrency"]
    ; destination_payment_rail : string option
         [@key "destinationPaymentRail"] [@default None]
    ; exchange_rate : float [@key "exchangeRate"]
    ; fees : Fees.t option [@default None]
    ; min_sending_amount : int option [@key "minSendingAmount"] [@default None]
    ; max_sending_amount : int option [@key "maxSendingAmount"] [@default None]
    ; sending_amount : int option [@key "sendingAmount"] [@default None]
    ; receiving_amount : int option [@key "receivingAmount"] [@default None]
    ; updated_at : string option [@key "updatedAt"] [@default None]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Quote = struct
  type t =
    { id : string
    ; status : string
    ; created_at : string [@key "createdAt"]
    ; expires_at : string [@key "expiresAt"]
    ; sending_currency : Currency.t [@key "sendingCurrency"]
    ; receiving_currency : Currency.t [@key "receivingCurrency"]
    ; total_sending_amount : int [@key "totalSendingAmount"]
    ; total_receiving_amount : int [@key "totalReceivingAmount"]
    ; exchange_rate : float [@key "exchangeRate"]
    ; fees_included : int [@key "feesIncluded"]
    ; transaction_id : string option [@key "transactionId"] [@default None]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end

module Page = struct
  type 'a t =
    { data : 'a list
    ; has_more : bool
    ; next_cursor : string option
    ; total_count : int option
    }
  [@@deriving sexp, compare, equal]

  let of_json item_of_json json =
    let open Yojson.Safe.Util in
    { data = List.map (to_list (member "data" json)) ~f:item_of_json
    ; has_more =
        (match member "hasMore" json with
         | `Bool b -> b
         | _ -> false)
    ; next_cursor = to_string_option (member "nextCursor" json)
    ; total_count = to_int_option (member "totalCount" json)
    }
  ;;
end

module Error_body = struct
  type t =
    { code : string
    ; reason : string option [@default None]
    }
  [@@deriving sexp, compare, equal, yojson] [@@yojson.allow_extra_fields]
end
