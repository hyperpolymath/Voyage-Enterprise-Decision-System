defmodule Veds.Application do
  @moduledoc """
  VEDS Application - Voyage Enterprise Decision System

  Main application supervisor. Starts all required services:
  - Phoenix endpoint (HTTP/WebSocket)
  - Redis/Dragonfly connection pool
  - Background job processor (Oban)
  - Telemetry
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Telemetry
      VedsWeb.Telemetry,

      # PubSub for real-time tracking
      {Phoenix.PubSub, name: Veds.PubSub},

      # Redis/Dragonfly connection
      {Redix,
       name: :redix,
       host: redis_host(),
       port: redis_port(),
       password: redis_password()},

      # gRPC connection to optimizer
      {Veds.Optimizer.Client, []},

      # Background jobs
      {Oban, Application.fetch_env!(:veds, Oban)},

      # Phoenix endpoint
      VedsWeb.Endpoint,

      # Tracking event consumer
      {Veds.Tracking.Consumer, []}
    ]

    opts = [strategy: :one_for_one, name: Veds.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    VedsWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp redis_host do
    System.get_env("DRAGONFLY_URL", "redis://localhost:6379")
    |> URI.parse()
    |> Map.get(:host, "localhost")
  end

  defp redis_port do
    System.get_env("DRAGONFLY_URL", "redis://localhost:6379")
    |> URI.parse()
    |> Map.get(:port, 6379)
  end

  defp redis_password do
    System.get_env("DRAGONFLY_PASS")
  end
end
