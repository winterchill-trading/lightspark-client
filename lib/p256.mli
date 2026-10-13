(** ECDSA verification on NIST P-256 (secp256r1) with SHA-256, over zarith.

    Only verification: it handles public data, so it does not need to be constant time.
    Written because mirage-crypto-ec cannot be installed on the OxCaml switch (its
    digestif dependency does not compile there). *)

open! Core

type public_key

(** PEM [-----BEGIN PUBLIC KEY-----] (SubjectPublicKeyInfo, uncompressed point). *)
val public_key_of_pem : string -> public_key Or_error.t

(** 65-byte uncompressed point [04 || X || Y]. *)
val public_key_of_octets : string -> public_key Or_error.t

(** [signature] is DER ([SEQUENCE { INTEGER r, INTEGER s }]) or raw 64-byte [r || s].
    [message] is hashed with SHA-256 here. *)
val verify : public_key -> message:string -> signature:string -> bool
