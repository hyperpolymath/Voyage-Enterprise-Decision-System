defmodule Veds.Tracking.Consumer do
  @moduledoc """
  Consumes position updates from Dragonfly pub/sub and broadcasts to WebSocket clients.

  Listens to:
  - Position updates from carrier GPS/AIS feeds
  - ETA updates from the tracking engine
  - Alerts (delays, deviations)
  """

  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Subscribe to Dragonfly pub/sub channels
    {:ok, pubsub} = Redix.PubSub.start_link()
    {:ok, _ref} = Redix.PubSub.subscribe(pubsub, "tracking:positions", self())
    {:ok, _ref} = Redix.PubSub.subscribe(pubsub, "tracking:etas", self())
    {:ok, _ref} = Redix.PubSub.subscribe(pubsub, "tracking:alerts", self())

    Logger.info("Tracking consumer started, subscribed to Dragonfly channels")

    {:ok, %{pubsub: pubsub}}
  end

  @impl true
  def handle_info({:redix_pubsub, _pubsub, _ref, :subscribed, %{channel: channel}}, state) do
    Logger.debug("Subscribed to #{channel}")
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:redix_pubsub, _pubsub, _ref, :message, %{channel: "tracking:positions", payload: payload}},
        state
      ) do
    case Jason.decode(payload) do
      {:ok, position} ->
        broadcast_position(position)

      {:error, reason} ->
        Logger.warning("Failed to decode position: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:redix_pubsub, _pubsub, _ref, :message, %{channel: "tracking:etas", payload: payload}},
        state
      ) do
    case Jason.decode(payload) do
      {:ok, eta} ->
        broadcast_eta(eta)

      {:error, reason} ->
        Logger.warning("Failed to decode ETA: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:redix_pubsub, _pubsub, _ref, :message, %{channel: "tracking:alerts", payload: payload}},
        state
      ) do
    case Jason.decode(payload) do
      {:ok, alert} ->
        broadcast_alert(alert)

      {:error, reason} ->
        Logger.warning("Failed to decode alert: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private helpers

  defp broadcast_position(%{"shipment_id" => shipment_id} = position) do
    Phoenix.PubSub.broadcast(
      Veds.PubSub,
      "position:#{shipment_id}",
      {:position_update, position}
    )
  end

  defp broadcast_position(_), do: :ok

  defp broadcast_eta(%{"shipment_id" => shipment_id} = eta) do
    Phoenix.PubSub.broadcast(
      Veds.PubSub,
      "position:#{shipment_id}",
      {:eta_update, eta}
    )
  end

  defp broadcast_eta(_), do: :ok

  defp broadcast_alert(%{"shipment_id" => shipment_id} = alert) do
    Phoenix.PubSub.broadcast(
      Veds.PubSub,
      "position:#{shipment_id}",
      {:alert, alert}
    )

    # Also store alert in database
    store_alert(alert)
  end

  defp broadcast_alert(_), do: :ok

  defp store_alert(alert) do
    # Store in SurrealDB via tracking events table
    # TODO: Implement
    Logger.info("Alert: #{inspect(alert)}")
  end
end
