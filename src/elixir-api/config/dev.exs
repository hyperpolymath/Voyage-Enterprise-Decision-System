import Config

# Development configuration

config :veds, VedsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_must_be_at_least_64_bytes_long_for_security_purposes_ok",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:veds, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:veds, ~w(--watch)]}
  ]

# Live reload
config :veds, VedsWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/veds_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes
config :veds, dev_routes: true

# Development logging
config :logger, :console, format: "[$level] $message\n"

# Phoenix LiveView development configuration
config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true

# Disable Oban in development (can be enabled manually)
config :veds, Oban, testing: :inline
