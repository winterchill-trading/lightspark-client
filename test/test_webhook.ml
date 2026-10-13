open! Core
open! Async
open Lightspark_client

(* Signed with a throwaway P-256 key via [openssl dgst -sha256 -sign]; same vector as the
   P256 unit test. *)
let pem =
  {|-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEDd+o8YVIIpkzm3cCvlVGx83S4vxn
IRdbQtr8WPmCE08fXlBi16JHEzamnoTjcfzwIfSnIfXUCVqSWkPYEh7gIg==
-----END PUBLIC KEY-----
|}
;;

let body =
  {|{"id":"Webhook:019542f5-b3e7-1d02-0000-000000000007","type":"INCOMING_PAYMENT.COMPLETED","timestamp":"2026-10-13T12:00:00Z","data":{"id":"Transaction:019542f5-b3e7-1d02-0000-000000000005","status":"COMPLETED"}}|}
;;

let signature =
  "MEUCIQCbmgAFv0vBz+GJ2oHhRR6dunDPiT2WOSZ16tIdK1xdSAIgZINpxyZzCMtF0RdIZ+BMVhuOZG8cw/H0WlGnvAGPfwo="
;;

let%expect_test "grid webhook" =
  let public_key = P256.public_key_of_pem pem |> Or_error.ok_exn in
  let verify ~body ~signature =
    print_s
      [%sexp
        (Webhook.Grid.verify ~public_key ~body ~signature : Webhook.Grid.event Or_error.t)]
  in
  verify ~body ~signature;
  (* The header may also carry the JSON envelope. *)
  verify ~body ~signature:(sprintf {|{"v":"1","s":"%s"}|} signature);
  verify
    ~body:(String.substr_replace_first body ~pattern:"COMPLETED" ~with_:"FAILED")
    ~signature;
  [%expect
    {|
    (Ok
     ((id Webhook:019542f5-b3e7-1d02-0000-000000000007)
      (type_ INCOMING_PAYMENT.COMPLETED) (timestamp 2026-10-13T12:00:00Z)
      (data
       "{\"id\":\"Transaction:019542f5-b3e7-1d02-0000-000000000005\",\"status\":\"COMPLETED\"}")))
    (Ok
     ((id Webhook:019542f5-b3e7-1d02-0000-000000000007)
      (type_ INCOMING_PAYMENT.COMPLETED) (timestamp 2026-10-13T12:00:00Z)
      (data
       "{\"id\":\"Transaction:019542f5-b3e7-1d02-0000-000000000005\",\"status\":\"COMPLETED\"}")))
    (Error "grid webhook signature mismatch")
    |}];
  return ()
;;
