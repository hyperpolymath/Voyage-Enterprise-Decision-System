defmodule Veds.MixProject do
  use Mix.Project

  def project do
    [
      app: :veds,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      name: "VEDS",
      description: "Voyage Enterprise Decision System - API Gateway",
      docs: [
        main: "Veds",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      mod: {Veds.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Phoenix
      {:phoenix, "~> 1.7.10"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 0.20.1"},
      {:phoenix_live_dashboard, "~> 0.8.2"},
      {:phoenix_pubsub, "~> 2.1"},

      # HTTP server
      {:plug_cowboy, "~> 2.6"},
      {:bandit, "~> 1.2"},

      # JSON
      {:jason, "~> 1.4"},

      # HTTP client
      {:req, "~> 0.4"},
      {:tesla, "~> 1.8"},

      # Redis/Dragonfly
      {:redix, "~> 1.3"},

      # gRPC client (for Rust optimizer)
      {:grpc, "~> 0.7"},
      {:protobuf, "~> 0.12"},

      # Database (for direct queries)
      {:ecto, "~> 3.11"},

      # Background jobs
      {:oban, "~> 2.17"},

      # Telemetry & monitoring
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:opentelemetry, "~> 1.3"},
      {:opentelemetry_exporter, "~> 1.6"},

      # Utilities
      {:decimal, "~> 2.1"},
      {:timex, "~> 3.7"},
      {:uuid, "~> 1.1"},

      # Development
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},

      # Testing
      {:floki, ">= 0.30.0", only: :test},
      {:ex_machina, "~> 2.7", only: :test},

      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind veds", "esbuild veds"],
      "assets.deploy": [
        "tailwind veds --minify",
        "esbuild veds --minify",
        "phx.digest"
      ]
    ]
  end
end
