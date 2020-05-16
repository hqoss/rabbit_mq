defmodule RabbitMQ.Connection do
  @moduledoc """
  Convenience to open and maintain a `AMQP.Connection`.

  Should be started under a `Supervisor`.
  """

  alias AMQP.Connection

  require Logger

  use GenServer

  @connection_opts ~w(max_channels heartbeat_interval_sec reconnect_interval_ms)a
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

  ######################
  # Callback Functions #
  ######################

  @impl true
  def init(connection_opts) do
    connect(connection_opts)
  end

  @impl true
  def handle_call(:get, _from, %Connection{} = connection), do: {:reply, connection, connection}

  @impl true
  def handle_info({:DOWN, _, :process, _pid, reason}, %Connection{} = connection) do
    Logger.warn("Connection to broker lost due to #{inspect(reason)}.")

    # Stop GenServer; will be restarted by Supervisor. Linked processes will be terminated,
    # and all channels implicitly closed due to the connection process being down.
    {:stop, {:connection_lost, reason}, connection}
  end

  @doc """
  Invoked when the server is about to exit. It should do any cleanup required.
  See https://hexdocs.pm/elixir/GenServer.html#c:terminate/2 for more details.
  """
  @impl true
  def terminate(reason, %Connection{} = connection) do
    Logger.warn("Terminating Connection server: #{inspect(reason)}.")

    if Process.alive?(connection.pid) do
      :ok = Connection.close(connection)
    end

    {:noreply, connection}
  end

  #####################
  # Private Functions #
  #####################

  defp connect(connection_opts) do
    max_channels = Keyword.get(connection_opts, :max_channels, 8)
    heartbeat_interval_sec = Keyword.get(connection_opts, :heartbeat_interval_sec, 30)
    reconnect_interval_ms = Keyword.get(connection_opts, :reconnect_interval_ms, 2500)

    opts = [channel_max: max_channels, heartbeat: heartbeat_interval_sec]

    amqp_url()
    |> Connection.open(opts)
    |> case do
      {:ok, connection} ->
        # Get notifications when the connection goes down
        Process.monitor(connection.pid)
        {:ok, connection}

      {:error, error} ->
        Logger.error("Failed to connect to broker due to #{inspect(error)}. Retrying...")
        :timer.sleep(reconnect_interval_ms)
        connect(connection_opts)
    end
  end

  defp amqp_url, do: Application.fetch_env!(:rabbit_mq, :amqp_url)
end
