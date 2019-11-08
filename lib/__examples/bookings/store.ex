defmodule Bookings.Store do
  use GenServer

  defmodule State do
    defstruct ongoing_bookings_count: 0
  end

  @this_module __MODULE__
  @registry :bookings_db
  @insert_booking_attrs ~w(id inserted_at date_time flight_number external_booking_id)a

  def start_link(_opts) do
    GenServer.start_link(@this_module, nil, name: @this_module)
  end

  def insert(%{date_time: _, flight_number: _, external_booking_id: _} = booking_data) do
    GenServer.call(@this_module, {:insert, booking_data})
  end

  def get_existing(id) when is_binary(id) do
    GenServer.call(@this_module, {:get_existing, id})
  end

  def delete(id) when is_binary(id) do
    GenServer.call(@this_module, {:delete, id})
  end

  def get_all() do
    GenServer.call(@this_module, :get_all)
  end

  def delete_all() do
    GenServer.call(@this_module, :delete_all)
  end

  @impl true
  def init(_arg) do
    _ = :ets.new(@registry, [:set, :private, :named_table, read_concurrency: true])
    {:ok, %State{}}
  end

  @impl true
  def handle_call({:insert, booking_data}, _from, %State{} = state) do
    id = UUID.uuid4()

    # Not matching this would be a developer error, so we let it fail.
    {:ok, attrs} =
      booking_data
      |> Map.put(:id, id)
      |> Map.put(:inserted_at, now_unix_ms())
      |> validate_required_keys(@insert_booking_attrs)

    case :ets.insert_new(@registry, {id, attrs}) do
      true -> {:reply, {:ok, attrs}, state}
      _ -> {:reply, {:error, :insert_failed}, state}
    end
  end

  @impl true
  def handle_call({:get_existing, id}, _from, %State{} = state) do
    case :ets.lookup(@registry, id) do
      [{^id, booking_data}] -> {:reply, {:ok, booking_data}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:delete, id}, _from, %State{} = state) do
    true = :ets.delete(@registry, id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_all, _from, %State{} = state) do
    bookings = :ets.match_object(@registry, {:"$1", :"$2"})
    {:reply, {:ok, bookings}, state}
  end

  @impl true
  def handle_call(:delete_all, _from, %State{} = state) do
    true = :ets.match_delete(@registry, {:_, :_})
    {:reply, :ok, state}
  end

  defp now_unix_ms, do: DateTime.utc_now() |> DateTime.to_unix(:millisecond)

  defp validate_required_keys(map, keys) do
    attrs = Map.take(map, keys)

    case Enum.all?(keys, &Map.has_key?(attrs, &1)) do
      true -> {:ok, attrs}
      _ -> {:error, :required_keys_missing}
    end
  end
end
