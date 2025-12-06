defmodule VedsWeb.API.V1.ShipmentController do
  use VedsWeb, :controller

  alias Veds.Shipments
  alias Veds.Optimizer

  action_fallback VedsWeb.FallbackController

  @doc """
  List shipments with optional filters
  """
  def index(conn, params) do
    filters = parse_filters(params)
    shipments = Shipments.list_shipments(filters)

    conn
    |> put_status(:ok)
    |> json(%{data: shipments, meta: %{count: length(shipments)}})
  end

  @doc """
  Create a new shipment
  """
  def create(conn, %{"shipment" => shipment_params}) do
    case Shipments.create_shipment(shipment_params) do
      {:ok, shipment} ->
        conn
        |> put_status(:created)
        |> json(%{data: shipment})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc """
  Get a single shipment
  """
  def show(conn, %{"id" => id}) do
    case Shipments.get_shipment(id) do
      {:ok, shipment} ->
        json(conn, %{data: shipment})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shipment not found"})
    end
  end

  @doc """
  Update a shipment
  """
  def update(conn, %{"id" => id, "shipment" => shipment_params}) do
    with {:ok, shipment} <- Shipments.get_shipment(id),
         {:ok, updated} <- Shipments.update_shipment(shipment, shipment_params) do
      json(conn, %{data: updated})
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shipment not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc """
  Delete a shipment
  """
  def delete(conn, %{"id" => id}) do
    with {:ok, shipment} <- Shipments.get_shipment(id),
         {:ok, _} <- Shipments.delete_shipment(shipment) do
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shipment not found"})
    end
  end

  @doc """
  Optimize routes for a shipment

  Calls the Rust optimizer via gRPC and stores candidate routes.
  """
  def optimize(conn, %{"id" => id} = params) do
    with {:ok, shipment} <- Shipments.get_shipment(id),
         {:ok, routes} <- Optimizer.optimize_routes(shipment, params) do
      # Update shipment status
      Shipments.update_status(shipment, "routed")

      conn
      |> put_status(:ok)
      |> json(%{
        data: %{
          shipment_id: id,
          routes: routes,
          optimization_time_ms: routes[:optimization_time_ms],
          candidates_evaluated: routes[:candidates_evaluated]
        }
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shipment not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Optimization failed", reason: inspect(reason)})
    end
  end

  @doc """
  Get routes for a shipment
  """
  def routes(conn, %{"id" => id}) do
    case Shipments.get_routes(id) do
      {:ok, routes} ->
        json(conn, %{data: routes})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shipment not found"})
    end
  end

  # Private helpers

  defp parse_filters(params) do
    %{}
    |> maybe_add_filter(:status, params["status"])
    |> maybe_add_filter(:shipper_id, params["shipper_id"])
    |> maybe_add_filter(:origin, params["origin"])
    |> maybe_add_filter(:destination, params["destination"])
  end

  defp maybe_add_filter(filters, _key, nil), do: filters
  defp maybe_add_filter(filters, key, value), do: Map.put(filters, key, value)

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp format_errors(errors), do: errors
end
