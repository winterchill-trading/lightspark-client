(lang dune 3.17)

(name lightspark-client)

(generate_opam_files true)

(license MIT)

(maintainers "winterchill-trading")

(authors "winterchill-trading")

(source
 (github winterchill-trading/lightspark-client))

(package
 (name lightspark-client)
 (synopsis "Async client for the Lightspark GraphQL and Grid APIs")
 (depends
  (ocaml
   (>= 5.2))
  dune
  core
  core_unix
  async
  async_ssl
  venue-net
  ppx_jane
  ppx_yojson_conv
  yojson
  uri
  cryptokit
  base64
  eqaf))
