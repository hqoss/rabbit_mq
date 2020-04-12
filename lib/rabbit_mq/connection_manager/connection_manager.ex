defmodule RabbitMQ.ConnectionManager do
  alias AMQP.{Connection, Channel}

  require Logger

  use GenServer

  @amqp_url Application.get_env(:rabbit_mq_ex, :amqp_url)
  @heartbeat_interval_sec Application.get_env(:rabbit_mq_ex, :heartbeat_interval_sec)
  @reconnect_interval_ms Application.get_env(:rabbit_mq_ex, :reconnect_interval_ms)
  @max_channels Application.get_env(:rabbit_mq_ex, :max_channels_per_connection)
  @this_module __MODULE__

  defmodule State do
    defstruct connection_count: 0
  end

  ##############
  # Public API #
  ##############

  def start_link(opts) do
    GenServer.start_link(@this_module, nil, name: @this_module)
  end

  def open_connection(channel_count, module_name)
      when channel_count <= @max_channels and is_atom(module_name) do
    connection_name = build_connection_name(module_name)
    GenServer.call(@this_module, {:open_connection, channel_count, connection_name})
  end

  def get_channel(%Connection{pid: connection_pid}) do
    GenServer.call(@this_module, {:get_channel, connection_pid})
  end

  ######################
  # Callback Functions #
  ######################

  @impl true
  def init(args) do
    # Process.flag(:trap_exit, true)
    {:ok, %State{}}
  end

  @impl true
  def handle_call(
        {:open_connection, channel_count, name},
        _from,
        %State{connection_count: connection_count} = state
      ) do
    {:ok, connection} = connect(name)

    channels =
      1..channel_count
      |> Enum.map(fn _ ->
        {:ok, channel} = Channel.open(connection)
        channel
      end)

    next_state =
      state
      |> Map.put(connection.pid, %{
        connection: connection,
        channels: channels,
        channel_count: channel_count,
        current_channel_offset: 0
      })
      |> Map.replace!(:connection_count, connection_count + 1)

    {:reply, {:ok, connection}, next_state}
  end

  @impl true
  def handle_call({:get_channel, connection_pid}, _from, %State{} = state) do
    connection = Map.get(state, connection_pid) |> IO.inspect(label: "conn")

    %{
      channels: channels,
      channel_count: channel_count,
      current_channel_offset: current_channel_offset
    } = connection

    index = rem(current_channel_offset, channel_count)
    channel = Enum.at(channels, index)

    next_connection = %{connection | current_channel_offset: current_channel_offset + 1}
    next_state = Map.replace!(state, connection_pid, next_connection)

    {:reply, {:ok, channel}, next_state}
  end

  @impl true
  def handle_info(
        {:DOWN, _, :process, pid, reason},
        %State{connection_count: connection_count} = state
      ) do
    Logger.error("Connection to broker lost due to #{inspect(reason)}.")

    next_state =
      state
      |> Map.delete(pid)
      |> Map.replace!(:connection_count, connection_count - 1)

    {:noreply, next_state}
  end

  #####################
  # Private Functions #
  #####################

  defp connect(name) do
    opts = [channel_max: @max_channels, heartbeat: @heartbeat_interval_sec]

    @amqp_url
    |> Connection.open(name, opts)
    |> case do
      {:ok, connection} ->
        # Get notifications when the connection goes down
        Process.monitor(connection.pid)
        {:ok, connection}

      {:error, error} ->
        Logger.error("Failed to connect to broker due to #{inspect(error)}. Retrying...")
        :timer.sleep(@reconnect_interval_ms)
        connect(name)
    end
  end

  defp build_connection_name(module_name) do
    {:ok, hostname} = :inet.gethostname()
    node = Node.self()
    "#{module_name}/#{hostname}/#{node}"
  end
end
