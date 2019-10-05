defmodule MQ.ConnectionManager do
  alias AMQP.{Channel, Confirm, Connection}
  alias MQ.ChannelRegistry

  require Logger

  use GenServer

  @this_module __MODULE__
  @amqp_url "amqp://guest:guest@localhost:5672"
  @reconnect_after_ms 5_000

  defmodule State do
    defstruct connection: nil
  end

  @spec start_link(list()) :: GenServer.on_start()
  def start_link(_opts) do
    Logger.info("Starting Connection Manager...")

    # `name: @this_module` makes it callable via the module name.
    GenServer.start_link(@this_module, %State{}, name: @this_module)
  end

  @spec request_channel(atom()) :: {:ok, Channel.t()} | {:error, any()}
  def request_channel(server_name) when is_atom(server_name) do
    GenServer.call(@this_module, {:request_channel, server_name, :normal})
  end

  @doc """
  See https://hexdocs.pm/amqp/AMQP.Confirm.html for more details.
  """
  @spec request_confirm_channel(atom()) :: {:ok, Channel.t()} | {:error, any()}
  def request_confirm_channel(server_name) when is_atom(server_name) do
    GenServer.call(@this_module, {:request_channel, server_name, :confirm})
  end

  @impl true
  def init(%State{} = initial_state) do
    :ok = ChannelRegistry.init()
    _ = connect()

    {:ok, initial_state}
  end

  @impl true
  def handle_call(
        {:request_channel, _server_name, _channel_type},
        _from,
        %State{connection: nil} = state
      ),
      do: {:reply, {:error, :no_connection}, state}

  @impl true
  def handle_call(
        {:request_channel, server_name, channel_type},
        _from,
        %State{connection: %Connection{} = connection} = state
      ) do
    server_name
    |> ChannelRegistry.lookup()
    |> case do
      {:ok, %Channel{}} = reply ->
        {:reply, reply, state}

      {:error, :channel_not_found} ->
        {:reply, open_channel(connection, server_name, channel_type), state}
    end
  end

  @impl true
  def handle_info(:connect, %State{} = state) do
    # TODO make amqp_url configurable
    case Connection.open(@amqp_url) do
      {:ok, %Connection{pid: pid} = connection} ->
        Logger.info("Connected to #{@amqp_url}.")

        # We will get notified when the connection is down
        # and exit the process cleanly.
        #
        # See how we handle `{:DOWN, _, :process, _pid, reason}`.
        Process.monitor(pid)

        {:noreply, %{state | connection: connection}}

      {:error, error} ->
        Logger.error(
          "Failed to connect to #{@amqp_url} due to #{inspect(error)}. Reconnecting in #{
            @reconnect_after_ms
          }ms."
        )

        connect(@reconnect_after_ms)

        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _, :process, _pid, reason}, _state) do
    Logger.error("Connection to #{@amqp_url} lost due to #{inspect(reason)}.")

    # Stop GenServer. Will be restarted by Supervisor.
    {:stop, {:connection_lost, reason}, %State{}}
  end

  defp connect(timeout_ms \\ 0) when is_integer(timeout_ms) do
    Process.send_after(self(), :connect, timeout_ms)
  end

  defp open_channel(connection, server_name, :confirm) do
    with {:ok, channel} <- Channel.open(connection),
         :ok <- Confirm.select(channel),
         :ok <- ChannelRegistry.insert(server_name, channel) do
      {:ok, channel}
    end
  end

  defp open_channel(connection, server_name, :normal) do
    with {:ok, channel} <- Channel.open(connection),
         :ok <- ChannelRegistry.insert(server_name, channel) do
      {:ok, channel}
    end
  end
end
