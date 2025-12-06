defmodule VedsWeb.TrackingSocket do
  @moduledoc """
  WebSocket for real-time shipment tracking.

  Clients can subscribe to position updates for specific shipments.
  """

  use Phoenix.Socket

  channel "tracking:*", VedsWeb.TrackingChannel

  @impl true
  def connect(params, socket, _connect_info) do
    # TODO: Implement proper authentication
    # For now, allow all connections
    {:ok, assign(socket, :client_id, params["client_id"] || UUID.uuid4())}
  end

  @impl true
  def id(socket), do: "tracking:#{socket.assigns.client_id}"
end

defmodule VedsWeb.TrackingChannel do
  @moduledoc """
  Channel for tracking a specific shipment.

  Topic format: "tracking:{shipment_id}"
  """

  use VedsWeb, :channel
  alias Veds.Tracking
  require Logger

  @impl true
  def join("tracking:" <> shipment_id, _params, socket) do
    # Verify shipment exists
    case Tracking.get_current_position(shipment_id) do
      {:ok, position} ->
        # Subscribe to position updates
        Phoenix.PubSub.subscribe(Veds.PubSub, "position:#{shipment_id}")

        # Send current position immediately
        send(self(), {:after_join, position})

        {:ok, assign(socket, :shipment_id, shipment_id)}

      {:error, :not_found} ->
        {:error, %{reason: "shipment_not_found"}}
    end
  end

  @impl true
  def handle_info({:after_join, position}, socket) do
    push(socket, "position", position)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:position_update, position}, socket) do
    push(socket, "position", position)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:eta_update, eta}, socket) do
    push(socket, "eta", eta)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:alert, alert}, socket) do
    push(socket, "alert", alert)
    {:noreply, socket}
  end

  @impl true
  def handle_in("get_history", %{"limit" => limit}, socket) do
    shipment_id = socket.assigns.shipment_id

    case Tracking.get_position_history(shipment_id, limit: limit) do
      {:ok, history} ->
        {:reply, {:ok, %{history: history}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("get_eta", _params, socket) do
    shipment_id = socket.assigns.shipment_id

    case Tracking.get_eta(shipment_id) do
      {:ok, eta} ->
        {:reply, {:ok, eta}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    Phoenix.PubSub.unsubscribe(Veds.PubSub, "position:#{socket.assigns.shipment_id}")
    :ok
  end
end
