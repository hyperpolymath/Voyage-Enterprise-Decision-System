# VEDS Configuration

import Config

# General application configuration
config :veds,
  generators: [timestamp_type: :utc_datetime]

# Endpoint configuration
config :veds, VedsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: VedsWeb.ErrorHTML, json: VedsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Veds.PubSub,
  live_view: [signing_salt: "veds_live"]

# Oban configuration (background jobs)
config :veds, Oban,
  repo: Veds.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # Refresh constraint cache every 5 minutes
       {"*/5 * * * *", Veds.Jobs.SyncConstraints},
       # Clean up old tracking data daily
       {"0 2 * * *", Veds.Jobs.CleanupTracking}
     ]}
  ],
  queues: [default: 10, tracking: 20, optimization: 5]

# JSON library
config :phoenix, :json_library, Jason

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :shipment_id]

# Import environment specific config
import_config "#{config_env()}.exs"
