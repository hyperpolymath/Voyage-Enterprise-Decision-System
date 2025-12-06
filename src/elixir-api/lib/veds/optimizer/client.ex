defmodule Veds.Optimizer.Client do
  @moduledoc """
  gRPC client for the Rust route optimizer.

  Provides a high-level interface to the optimization service.
  """

  use GenServer
  require Logger

  @default_timeout 30_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Optimize routes for a shipment.

  Returns `{:ok, routes}` or `{:error, reason}`.
  """
  def optimize_routes(shipment, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    request = build_optimize_request(shipment, opts)
    GenServer.call(__MODULE__, {:optimize, request}, timeout)
  end

  @doc """
  Evaluate constraints for a route.
  """
  def evaluate_constraints(route, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    request = %{
      route_id: route.id,
      route: route,
      constraint_ids: Keyword.get(opts, :constraint_ids, [])
    }

    GenServer.call(__MODULE__, {:evaluate, request}, timeout)
  end

  @doc """
  Get the optimizer graph status.
  """
  def graph_status do
    GenServer.call(__MODULE__, :graph_status)
  end

  @doc """
  Reload the transport graph.
  """
  def reload_graph do
    GenServer.call(__MODULE__, :reload_graph, @default_timeout)
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    optimizer_url = System.get_env("OPTIMIZER_URL", "http://localhost:50051")

    state = %{
      url: optimizer_url,
      channel: nil,
      connected: false
    }

    # Connect in background
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect_to_optimizer(state.url) do
      {:ok, channel} ->
        Logger.info("Connected to optimizer at #{state.url}")
        {:noreply, %{state | channel: channel, connected: true}}

      {:error, reason} ->
        Logger.warning("Failed to connect to optimizer: #{inspect(reason)}. Retrying in 5s...")
        Process.send_after(self(), :connect, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:optimize, request}, _from, %{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:optimize, request}, _from, state) do
    # For now, use HTTP until gRPC is fully set up
    result = call_optimizer_http(state.url, "/optimize", request)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:evaluate, request}, _from, %{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:evaluate, request}, _from, state) do
    result = call_optimizer_http(state.url, "/evaluate", request)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:graph_status, _from, state) do
    result = call_optimizer_http(state.url, "/status", %{})
    {:reply, result, state}
  end

  @impl true
  def handle_call(:reload_graph, _from, state) do
    result = call_optimizer_http(state.url, "/reload", %{force: true})
    {:reply, result, state}
  end

  # Private helpers

  defp connect_to_optimizer(_url) do
    # TODO: Implement proper gRPC connection
    # For now, just validate the URL is reachable
    {:ok, nil}
  end

  defp call_optimizer_http(base_url, path, request) do
    url = "#{base_url}#{path}"

    case Req.post(url, json: request, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Optimizer call failed: #{inspect(e)}")
      {:error, e}
  end

  defp build_optimize_request(shipment, opts) do
    %{
      shipment_id: shipment.id,
      origin_port: shipment.origin,
      destination_port: shipment.destination,
      weight_kg: shipment.weight_kg,
      volume_m3: shipment.volume_m3,
      pickup_after: DateTime.to_iso8601(shipment.pickup_after),
      deliver_by: DateTime.to_iso8601(shipment.deliver_by),
      max_cost_usd: Keyword.get(opts, :max_cost),
      max_carbon_kg: Keyword.get(opts, :max_carbon),
      min_labor_score: Keyword.get(opts, :min_labor_score),
      allowed_modes: Keyword.get(opts, :allowed_modes, []),
      excluded_carriers: Keyword.get(opts, :excluded_carriers, []),
      max_routes: Keyword.get(opts, :max_routes, 10),
      max_segments: Keyword.get(opts, :max_segments, 8),
      cost_weight: Keyword.get(opts, :cost_weight, 0.4),
      time_weight: Keyword.get(opts, :time_weight, 0.3),
      carbon_weight: Keyword.get(opts, :carbon_weight, 0.2),
      labor_weight: Keyword.get(opts, :labor_weight, 0.1)
    }
  end
end
