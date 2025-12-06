import Config

# Runtime configuration - loaded at runtime, not compile time

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :veds, VedsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end

# Database URLs (all environments)
config :veds, :xtdb_url, System.get_env("XTDB_URL", "http://localhost:3000")
config :veds, :surrealdb_url, System.get_env("SURREALDB_URL", "ws://localhost:8000")
config :veds, :surrealdb_user, System.get_env("SURREALDB_USER", "root")
config :veds, :surrealdb_pass, System.get_env("SURREALDB_PASS", "veds_dev_password")
config :veds, :dragonfly_url, System.get_env("DRAGONFLY_URL", "redis://localhost:6379")
config :veds, :dragonfly_pass, System.get_env("DRAGONFLY_PASS")
config :veds, :optimizer_url, System.get_env("OPTIMIZER_URL", "http://localhost:50051")
