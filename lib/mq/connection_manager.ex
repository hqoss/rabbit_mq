defmodule MQ.ConnectionManager do
  alias AMQP.{Channel, Confirm, Connection}
  alias Core.ExponentialBackoff
  alias MQ.ChannelRegistry

  require Logger

  use GenServer

  @this_module __MODULE__
  @amqp_url "amqp://guest:guest@localhost:5672"

  defmodule State do
    defstruct connection: nil
  end

  @spec start_link(list()) :: GenServer.on_start()
  def start_link(_opts) do
    # `name: @this_module` makes it callable via the module name.
    GenServer.start_link(@this_module, %State{}, name: @this_module)
  end

  @spec request_channel(atom()) :: {:ok, Channel.t()} | {:error, any()}
  def request_channel(server_name) when is_atom(server_name) do
    ExponentialBackoff.with_backoff(fn ->
      GenServer.call(@this_module, {:request_channel, server_name, :normal})
    end)
  end

  @doc """
  See https://hexdocs.pm/amqp/AMQP.Confirm.html for more details.
  """
  @spec request_confirm_channel(atom()) :: {:ok, Channel.t()} | {:error, any()}
  def request_confirm_channel(server_name) when is_atom(server_name) do
    ExponentialBackoff.with_backoff(fn ->
      GenServer.call(@this_module, {:request_channel, server_name, :confirm})
    end)
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
  def handle_info({:connect, next_backoff}, %State{} = state) do
    case open_connection(next_backoff) do
      {:ok, %Connection{} = connection} ->
        monitor_connection(connection)
        {:noreply, %{state | connection: connection}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _, :process, _pid, reason}, _state) do
    Logger.error("Connection to #{@amqp_url} lost due to #{inspect(reason)}.")

    # Stop GenServer. Will be restarted by Supervisor.
    {:stop, {:connection_lost, reason}, %State{}}
  end

  defp connect(prev \\ 0, current \\ 1) when is_integer(prev) and is_integer(current) do
    {timeout_ms, _current, _next} =
      next_backoff = ExponentialBackoff.calc_timeout_ms(prev, current)

    Process.send_after(self(), {:connect, next_backoff}, timeout_ms)
  end

  defp open_connection({timeout_ms, current, next}) do
    # TODO make amqp_url configurable
    case Connection.open(@amqp_url) do
      {:ok, %Connection{}} = reply ->
        Logger.info("Connected to #{@amqp_url}.")
        reply

      {:error, error} = reply ->
        Logger.error(
          "Failed to connect to #{@amqp_url} due to #{inspect(error)}. Reconnecting in #{
            timeout_ms
          }ms."
        )

        connect(current, next)
        reply
    end
  end

  defp open_channel(%Connection{} = connection, server_name, :confirm) do
    Logger.debug("Opening a confirm channel for #{server_name}.")

    with {:ok, channel} <- Channel.open(connection),
         :ok <- Confirm.select(channel),
         :ok <- ChannelRegistry.insert(server_name, channel) do
      {:ok, channel}
    end
  end

  defp open_channel(%Connection{} = connection, server_name, :normal) do
    Logger.debug("Opening a channel for #{server_name}.")

    with {:ok, channel} <- Channel.open(connection),
         :ok <- ChannelRegistry.insert(server_name, channel) do
      {:ok, channel}
    end
  end

  # We will get notified when the connection is down
  # and exit the process cleanly.
  #
  # See how we handle `{:DOWN, _, :process, _pid, reason}`.
  defp monitor_connection(%Connection{pid: pid}) do
    Process.monitor(pid)
  end
end
