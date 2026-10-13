(** GraphQL documents for the server API.

    Fragments and aliases follow the official SDKs (lightsparkdev/python-sdk, js-sdk) so
    responses have the same shape the SDK parsers expect. Larger SDK documents are trimmed
    to the fields this client decodes. *)

val currency_amount_fragment : string
val account_fragment : string
val balances_fragment : string
val page_info_fragment : string
val invoice_fragment : string
val current_account : string
val account_nodes : string
val account_wallets : string
val account_transactions : string
val node_network : string
val invoice_for_payment_hash : string
val decoded_payment_request : string
val create_invoice : string
val create_test_mode_invoice : string
val create_test_mode_payment : string
val fund_node : string
val pay_invoice : string
