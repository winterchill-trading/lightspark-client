open! Core

let hex = Z.of_string_base 16
let p = hex "FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF"
let a = Z.sub p (Z.of_int 3)
let b = hex "5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B"
let n = hex "FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551"

type point =
  | Infinity
  | Affine of Z.t * Z.t

let g =
  Affine
    ( hex "6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296"
    , hex "4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5" )
;;

let modp x = Z.erem x p
let inv x m = Z.invert x m

let on_curve = function
  | Infinity -> false
  | Affine (x, y) ->
    Z.(geq x zero && lt x p && geq y zero && lt y p)
    && Z.equal (modp (Z.mul y y)) (modp Z.(add (add (mul x (mul x x)) (mul a x)) b))
;;

let double = function
  | Infinity -> Infinity
  | Affine (_, y) when Z.equal y Z.zero -> Infinity
  | Affine (x, y) ->
    let l = modp Z.(mul (add (mul (of_int 3) (mul x x)) a) (inv (mul (of_int 2) y) p)) in
    let x3 = modp Z.(sub (mul l l) (mul (of_int 2) x)) in
    let y3 = modp Z.(sub (mul l (sub x x3)) y) in
    Affine (x3, y3)
;;

let add p1 p2 =
  match p1, p2 with
  | Infinity, q | q, Infinity -> q
  | Affine (x1, y1), Affine (x2, y2) ->
    if Z.equal x1 x2
    then if Z.equal (modp (Z.add y1 y2)) Z.zero then Infinity else double p1
    else (
      let l = modp Z.(mul (sub y2 y1) (inv (erem (sub x2 x1) p) p)) in
      let x3 = modp Z.(sub (sub (mul l l) x1) x2) in
      let y3 = modp Z.(sub (mul l (sub x1 x3)) y1) in
      Affine (x3, y3))
;;

let mul k pt =
  let rec loop k acc addend =
    if Z.equal k Z.zero
    then acc
    else (
      let acc = if Z.testbit k 0 then add acc addend else acc in
      loop (Z.shift_right k 1) acc (double addend))
  in
  loop k Infinity pt
;;

type public_key = point

let z_of_bytes s =
  if String.is_empty s
  then Z.zero
  else
    Z.of_string_base 16 (String.concat_map s ~f:(fun c -> sprintf "%02x" (Char.to_int c)))
;;

let public_key_of_octets s =
  if String.length s = 65 && Char.equal s.[0] '\x04'
  then (
    let pt =
      Affine
        ( z_of_bytes (String.sub s ~pos:1 ~len:32)
        , z_of_bytes (String.sub s ~pos:33 ~len:32) )
    in
    if on_curve pt then Ok pt else Or_error.error_string "P-256 point is not on the curve")
  else Or_error.error_string "expected a 65-byte uncompressed P-256 point"
;;

(* DER prefix of a SubjectPublicKeyInfo for id-ecPublicKey with prime256v1, followed by
   the 65-byte point: SEQUENCE(89) { SEQUENCE(19) { OID 1.2.840.10045.2.1,
   OID 1.2.840.10045.3.1.7 }, BIT STRING(66) 00 }. *)
let spki_prefix =
  "\x30\x59\x30\x13\x06\x07\x2a\x86\x48\xce\x3d\x02\x01\x06\x08\x2a\x86\x48\xce\x3d\x03\x01\x07\x03\x42\x00"
;;

let public_key_of_pem pem =
  let body =
    String.split_lines pem
    |> List.map ~f:String.strip
    |> List.filter ~f:(fun l ->
      not (String.is_empty l || String.is_prefix l ~prefix:"-----"))
    |> String.concat
  in
  match Base64.decode body with
  | Error (`Msg m) -> Or_error.error_s [%message "invalid PEM base64" (m : string)]
  | Ok der ->
    if String.length der = 91 && String.is_prefix der ~prefix:spki_prefix
    then public_key_of_octets (String.drop_prefix der 26)
    else Or_error.error_string "not a P-256 SubjectPublicKeyInfo"
;;

(* Minimal DER reader for SEQUENCE [{ INTEGER r, INTEGER s }]; short and one-byte long
   lengths cover every P-256 signature. *)
let parse_der_signature s =
  let len = String.length s in
  let byte i = if i < len then Some (Char.to_int s.[i]) else None in
  let read_len i =
    match byte i with
    | Some l when l < 0x80 -> Some (l, i + 1)
    | Some 0x81 -> Option.map (byte (i + 1)) ~f:(fun l -> l, i + 2)
    | _ -> None
  in
  let read_int i =
    match byte i with
    | Some 0x02 ->
      Option.bind
        (read_len (i + 1))
        ~f:(fun (l, j) ->
          if l > 0 && j + l <= len
          then Some (z_of_bytes (String.sub s ~pos:j ~len:l), j + l)
          else None)
    | _ -> None
  in
  match byte 0 with
  | Some 0x30 ->
    Option.bind (read_len 1) ~f:(fun (l, j) ->
      if j + l <> len
      then None
      else
        Option.bind (read_int j) ~f:(fun (r, k) ->
          Option.bind (read_int k) ~f:(fun (s', m) ->
            if m = len then Some (r, s') else None)))
  | _ -> None
;;

let verify q ~message ~signature =
  let rs =
    match parse_der_signature signature with
    | Some rs -> Some rs
    | None when String.length signature = 64 ->
      Some
        ( z_of_bytes (String.sub signature ~pos:0 ~len:32)
        , z_of_bytes (String.sub signature ~pos:32 ~len:32) )
    | None -> None
  in
  match rs with
  | None -> false
  | Some (r, s) ->
    let in_range x = Z.(gt x zero && lt x n) in
    if not (in_range r && in_range s)
    then false
    else (
      let e = z_of_bytes (Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) message) in
      let w = inv s n in
      let u1 = Z.erem (Z.mul e w) n in
      let u2 = Z.erem (Z.mul r w) n in
      match add (mul u1 g) (mul u2 q) with
      | Infinity -> false
      | Affine (x, _) -> Z.equal (Z.erem x n) r)
;;

module%test Openssl_vectors = struct
  (* Key, body and signature made with [openssl dgst -sha256 -sign] (OpenSSL 4.0). *)
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
    Base64.decode_exn
      "MEUCIQCbmgAFv0vBz+GJ2oHhRR6dunDPiT2WOSZ16tIdK1xdSAIgZINpxyZzCMtF0RdIZ+BMVhuOZG8cw/H0WlGnvAGPfwo="
  ;;

  let key = public_key_of_pem pem |> Or_error.ok_exn

  let%expect_test "verify" =
    print_s [%sexp (verify key ~message:body ~signature : bool)];
    print_s [%sexp (verify key ~message:(body ^ " ") ~signature : bool)];
    let flipped = Bytes.of_string signature in
    Bytes.set flipped 10 (Char.of_int_exn (Char.to_int (Bytes.get flipped 10) lxor 1));
    print_s [%sexp (verify key ~message:body ~signature:(Bytes.to_string flipped) : bool)];
    print_s [%sexp (verify key ~message:body ~signature:"junk" : bool)];
    [%expect {|
        true
        false
        false
        false
        |}]
  ;;

  let%expect_test "rejects keys that are not P-256 points" =
    print_s [%sexp (Result.is_ok (public_key_of_pem "nope") : bool)];
    print_s
      [%sexp
        (Result.is_ok (public_key_of_octets ("\x04" ^ String.make 64 '\x01')) : bool)];
    [%expect {|
        false
        false
        |}]
  ;;
end
