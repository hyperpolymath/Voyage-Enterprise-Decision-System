import Config

# Production configuration

config :veds, VedsWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

# Production logging
config :logger, level: :info

# Runtime configuration via environment variables
config :veds, VedsWeb.Endpoint,
  url: [host: {:system, "PHX_HOST"}, port: 443, scheme: "https"]
