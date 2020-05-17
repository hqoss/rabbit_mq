defmodule RabbitMQ.Connection do
  @moduledoc """
  Convenience to open and maintain a `AMQP.Connection`.

  Should be started under a `Supervisor`.
  """

  require Logger

  use AMQP
  use GenServer

  @connection_opts ~w(heartbeat_interval_sec max_channels name reconnect_interval_ms)a
  @this_module __MODULE__

  ##############
  # Public API #
  ##############

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    connection_opts = Keyword.take(opts, @connection_opts)

    GenServer.start_link(@this_module, connection_opts, name: name)
  end

  @doc """
  Retrieves the `AMQP.Connection` from a given `RabbitMQ.Connection` server.
  """
  @spec get(atom()) :: Connection.t()
  def get(name) when is_atom(name) do
    GenServer.call(name, :get)
  end

  ######################
  # Callback Functions #
  ######################

  @impl true
  def init(connection_opts) do
    # This is needed to invoke `terminate/2` when the parent process,
    # ideally a `Supervisor`, sends an exit signal.
    #
    # Read more @ https://hexdocs.pm/elixir/GenServer.html#c:terminate/2.
    Process.flag(:trap_exit, true)

    connect(connection_opts)
  end

  @impl true
  def handle_call(:get, _from, %Connection{} = connection), do: {:reply, connection, connection}

  @impl true
  def handle_info({:DOWN, _, :process, _pid, reason}, %Connection{} = connection) do
    Logger.warn("Connection to broker lost due to #{inspect(reason)}.")

    # Stop GenServer; will be restarted by Supervisor.
    {:stop, {:connection_lost, reason}, connection}
  end

  @doc """
  Invoked when the server is about to exit. It should do any cleanup required.
  See https://hexdocs.pm/elixir/GenServer.html#c:terminate/2 for more details.
  """
  @impl true
  def terminate(reason, %Connection{} = connection) do
    Logger.warn("Terminating Connection server: #{inspect(reason)}.")

    # Not sure this check is needed.
    if Process.alive?(connection.pid) do
      :ok = Connection.close(connection)
    end

    {:noreply, connection}
  end

  #####################
  # Private Functions #
  #####################

  defp connect(connection_opts) do
    name = connection_name(connection_opts)

    heartbeat_interval_sec = Keyword.get(connection_opts, :heartbeat_interval_sec, 30)
    max_channels = Keyword.get(connection_opts, :max_channels, 8)
    reconnect_interval_ms = Keyword.get(connection_opts, :reconnect_interval_ms, 2500)

    opts = [channel_max: max_channels, heartbeat: heartbeat_interval_sec]

    amqp_url()
    |> Connection.open(name, opts)
    |> case do
      {:ok, connection} ->
        Logger.debug("Connected to broker")

        # Monitor the connection process. Should the process go down,
        # we will try to exit cleanly and let the supervisor restart the process.
        _ref = Process.monitor(connection.pid)

        {:ok, connection}

      {:error, error} ->
        Logger.error("Failed to connect to broker due to #{inspect(error)}. Retrying...")
        :timer.sleep(reconnect_interval_ms)
        connect(connection_opts)
    end
  end

  defp amqp_url, do: Application.fetch_env!(:rabbit_mq, :amqp_url)

  defp connection_name(connection_opts) do
    {:ok, name} = Keyword.fetch(connection_opts, :name)
    {:ok, hostname} = :inet.gethostname()
    "#{hostname}/#{name}"
  end
end
