(** Credentials and endpoints, read from the environment.

    The client defaults to [Sandbox]: writes that could move real money are refused unless
    the config was built with [~live:true]. *)

open! Core

module Mode : sig
  type t =
    | Sandbox
    | Live
  [@@deriving sexp, compare, equal]
end

type t = private
  { client_id : string
  ; client_secret : string
  ; graphql_url : Uri.t
  ; grid_url : Uri.t
  ; mode : Mode.t
  }

(** Shows the endpoints and the mode; the client id is cut to four characters and the
    secret is never printed. *)
val sexp_of_t : t -> Sexp.t

val default_graphql_url : Uri.t
val default_grid_url : Uri.t

val create
  :  ?graphql_url:Uri.t
  -> ?grid_url:Uri.t
  -> ?live:bool
  -> client_id:string
  -> client_secret:string
  -> unit
  -> t

(** Environment variable names. *)
val client_id_var : string

val client_secret_var : string
val graphql_url_var : string
val grid_url_var : string

(** Reads [LIGHTSPARK_CLIENT_ID], [LIGHTSPARK_CLIENT_SECRET] and the optional
    [LIGHTSPARK_GRAPHQL_URL] and [LIGHTSPARK_GRID_URL]. Empty values count as unset.
    [getenv] defaults to [Sys.getenv]. *)
val of_env : ?getenv:(string -> string option) -> ?live:bool -> unit -> t Or_error.t

val is_live : t -> bool
