(* Fragment texts copied from the official Python SDK (lightspark/objects/*.py). *)

let currency_amount_fragment =
  {|
fragment CurrencyAmountFragment on CurrencyAmount {
    __typename
    currency_amount_original_value: original_value
    currency_amount_original_unit: original_unit
    currency_amount_preferred_currency_unit: preferred_currency_unit
    currency_amount_preferred_currency_value_rounded: preferred_currency_value_rounded
    currency_amount_preferred_currency_value_approx: preferred_currency_value_approx
}
|}
;;

let account_fragment =
  {|
fragment AccountFragment on Account {
    __typename
    account_id: id
    account_created_at: created_at
    account_updated_at: updated_at
    account_name: name
}
|}
;;

let balances_fragment =
  {|
fragment BalancesFragment on Balances {
    __typename
    balances_owned_balance: owned_balance {
        ...CurrencyAmountFragment
    }
    balances_available_to_send_balance: available_to_send_balance {
        ...CurrencyAmountFragment
    }
    balances_available_to_withdraw_balance: available_to_withdraw_balance {
        ...CurrencyAmountFragment
    }
}
|}
;;

let page_info_fragment =
  {|
fragment PageInfoFragment on PageInfo {
    __typename
    page_info_has_next_page: has_next_page
    page_info_has_previous_page: has_previous_page
    page_info_start_cursor: start_cursor
    page_info_end_cursor: end_cursor
}
|}
;;

(* The SDK's InvoiceFragment minus [destination], a union of every node type. *)
let invoice_fragment =
  {|
fragment InvoiceFragment on Invoice {
    __typename
    invoice_id: id
    invoice_created_at: created_at
    invoice_updated_at: updated_at
    invoice_data: data {
        __typename
        invoice_data_encoded_payment_request: encoded_payment_request
        invoice_data_bitcoin_network: bitcoin_network
        invoice_data_payment_hash: payment_hash
        invoice_data_amount: amount {
            ...CurrencyAmountFragment
        }
        invoice_data_created_at: created_at
        invoice_data_expires_at: expires_at
        invoice_data_memo: memo
    }
    invoice_status: status
    invoice_amount_paid: amount_paid {
        ...CurrencyAmountFragment
    }
}
|}
;;

let current_account =
  {|
query GetCurrentAccount {
    current_account {
        ...AccountFragment
    }
}
|}
  ^ account_fragment
;;

let account_nodes =
  {|
query FetchAccountToNodesConnection($first: Int, $bitcoin_networks: [BitcoinNetwork!], $after: String) {
    current_account {
        nodes(first: $first, bitcoin_networks: $bitcoin_networks, after: $after) {
            __typename
            account_to_nodes_connection_count: count
            account_to_nodes_connection_page_info: page_info {
                ...PageInfoFragment
            }
            account_to_nodes_connection_entities: entities {
                __typename
                ... on LightsparkNode {
                    lightspark_node_id: id
                    lightspark_node_created_at: created_at
                    lightspark_node_display_name: display_name
                    lightspark_node_bitcoin_network: bitcoin_network
                    lightspark_node_public_key: public_key
                    lightspark_node_status: status
                    lightspark_node_balances: balances {
                        ...BalancesFragment
                    }
                }
            }
        }
    }
}
|}
  ^ page_info_fragment
  ^ balances_fragment
  ^ currency_amount_fragment
;;

let account_wallets =
  {|
query FetchAccountToWalletsConnection($first: Int, $after: String, $third_party_ids: [String!]) {
    current_account {
        wallets(first: $first, after: $after, third_party_ids: $third_party_ids) {
            __typename
            account_to_wallets_connection_count: count
            account_to_wallets_connection_page_info: page_info {
                ...PageInfoFragment
            }
            account_to_wallets_connection_entities: entities {
                __typename
                wallet_id: id
                wallet_created_at: created_at
                wallet_updated_at: updated_at
                wallet_last_login_at: last_login_at
                wallet_balances: balances {
                    ...BalancesFragment
                }
                wallet_third_party_identifier: third_party_identifier
                wallet_status: status
            }
        }
    }
}
|}
  ^ page_info_fragment
  ^ balances_fragment
  ^ currency_amount_fragment
;;

let account_transactions =
  {|
query FetchAccountToTransactionsConnection($first: Int, $after: String, $bitcoin_network: BitcoinNetwork, $lightning_node_id: ID) {
    current_account {
        transactions(first: $first, after: $after, bitcoin_network: $bitcoin_network, lightning_node_id: $lightning_node_id) {
            __typename
            account_to_transactions_connection_count: count
            account_to_transactions_connection_page_info: page_info {
                ...PageInfoFragment
            }
            account_to_transactions_connection_entities: entities {
                __typename
                transaction_id: id
                transaction_created_at: created_at
                transaction_updated_at: updated_at
                transaction_status: status
                transaction_resolved_at: resolved_at
                transaction_amount: amount {
                    ...CurrencyAmountFragment
                }
                transaction_transaction_hash: transaction_hash
            }
        }
    }
}
|}
  ^ page_info_fragment
  ^ currency_amount_fragment
;;

let node_network =
  {|
query NodeNetwork($node_id: ID!) {
    entity(id: $node_id) {
        __typename
        ... on LightsparkNode {
            lightspark_node_bitcoin_network: bitcoin_network
        }
    }
}
|}
;;

let invoice_for_payment_hash =
  {|
query InvoiceForPaymentHash($payment_hash: Hash32!) {
    invoice_for_payment_hash(input: {
        payment_hash: $payment_hash
    }) {
        invoice {
            ...InvoiceFragment
        }
    }
}
|}
  ^ invoice_fragment
  ^ currency_amount_fragment
;;

let decoded_payment_request =
  {|
query DecodedPaymentRequest(
    $encoded_payment_request: String!
) {
    decoded_payment_request(encoded_payment_request: $encoded_payment_request) {
        __typename
        ... on InvoiceData {
            __typename
            invoice_data_encoded_payment_request: encoded_payment_request
            invoice_data_bitcoin_network: bitcoin_network
            invoice_data_payment_hash: payment_hash
            invoice_data_amount: amount {
                ...CurrencyAmountFragment
            }
            invoice_data_created_at: created_at
            invoice_data_expires_at: expires_at
            invoice_data_memo: memo
        }
    }
}
|}
  ^ currency_amount_fragment
;;

let create_invoice =
  {|
mutation CreateInvoice(
    $node_id: ID!
    $amount_msats: Long!
    $memo: String
    $invoice_type: InvoiceType
    $expiry_secs: Int
) {
    create_invoice(input: {
        node_id: $node_id
        amount_msats: $amount_msats
        memo: $memo
        invoice_type: $invoice_type
        expiry_secs: $expiry_secs
    }) {
        invoice {
            ...InvoiceFragment
        }
    }
}
|}
  ^ invoice_fragment
  ^ currency_amount_fragment
;;

let create_test_mode_invoice =
  {|
mutation CreateTestModeInvoice(
    $local_node_id: ID!
    $amount_msats: Long!
    $memo: String
    $invoice_type: InvoiceType
) {
    create_test_mode_invoice(input: {
        local_node_id: $local_node_id
        amount_msats: $amount_msats
        memo: $memo
        invoice_type: $invoice_type
    }) {
        encoded_payment_request
    }
}
|}
;;

let create_test_mode_payment =
  {|
mutation CreateTestModePayment(
    $local_node_id: ID!
    $encoded_invoice: String!
    $amount_msats: Long
) {
    create_test_mode_payment(input: {
        local_node_id: $local_node_id
        encoded_invoice: $encoded_invoice
        amount_msats: $amount_msats
    }) {
        incoming_payment {
            __typename
            transaction_id: id
            transaction_created_at: created_at
            transaction_updated_at: updated_at
            transaction_status: status
            transaction_resolved_at: resolved_at
            transaction_amount: amount {
                ...CurrencyAmountFragment
            }
            transaction_transaction_hash: transaction_hash
        }
    }
}
|}
  ^ currency_amount_fragment
;;

let fund_node =
  {|
mutation FundNode(
    $node_id: ID!,
    $amount_sats: Long
) {
    fund_node(input: { node_id: $node_id, amount_sats: $amount_sats }) {
        amount {
            ...CurrencyAmountFragment
        }
    }
}
|}
  ^ currency_amount_fragment
;;

let pay_invoice =
  {|
mutation PayInvoice(
    $node_id: ID!
    $encoded_invoice: String!
    $timeout_secs: Int!
    $maximum_fees_msats: Long!
    $amount_msats: Long
    $idempotency_key: String
) {
    pay_invoice(input: {
        node_id: $node_id
        encoded_invoice: $encoded_invoice
        timeout_secs: $timeout_secs
        maximum_fees_msats: $maximum_fees_msats
        amount_msats: $amount_msats
        idempotency_key: $idempotency_key
    }) {
        payment {
            __typename
            transaction_id: id
            transaction_created_at: created_at
            transaction_updated_at: updated_at
            transaction_status: status
            transaction_resolved_at: resolved_at
            transaction_amount: amount {
                ...CurrencyAmountFragment
            }
            transaction_transaction_hash: transaction_hash
        }
    }
}
|}
  ^ currency_amount_fragment
;;
