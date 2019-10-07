defmodule MQ.ConnectionManager do
  alias AMQP.{Channel, Confirm, Connection}
  alias Core.ExponentialBackoff
  alias MQ.ChannelRegistry

  require Logger

  use GenServer

  @this_module __MODULE__
  @amqp_url "amqp://guest:guest@localhost:5672"

  defmodule State do
    @enforce_keys [:amqp_url]
    defstruct amqp_url: nil, connection: nil
  end

  @spec start_link(list()) :: GenServer.on_start()
  def start_link(opts) do
    # `name: @this_module` makes it callable via the module name.
    amqp_url = opts |> Keyword.get(:amqp_url, @amqp_url)
    GenServer.start_link(@this_module, %State{amqp_url: amqp_url}, name: @this_module)
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
  def init(%State{amqp_url: amqp_url} = initial_state) do
    :ok = ChannelRegistry.init()
    {:ok, %Connection{} = connection} = connect(amqp_url)
    {:ok, %{initial_state | connection: connection}}
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
  def handle_info({:DOWN, _, :process, _pid, reason}, %State{amqp_url: amqp_url} = state) do
    Logger.error("Connection to #{amqp_url} lost due to #{inspect(reason)}.")

    # Stop GenServer. Will be restarted by Supervisor.
    {:stop, {:connection_lost, reason}, %{state | connection: nil}}
  end

  defp connect(amqp_url) do
    ExponentialBackoff.with_backoff(fn ->
      case Connection.open(amqp_url) do
        {:ok, %Connection{} = connection} = reply ->
          Logger.debug("Connected to #{amqp_url}.")
          _ = monitor_connection(connection)
          reply

        error ->
          Logger.error("Error connecting to #{amqp_url}: #{inspect(error)}. Retrying...")
          error
      end
    end)
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
  defp monitor_connection(%Connection{pid: pid}), do: Process.monitor(pid)
end
