defmodule RabbitMQ.Consumer.Worker do
  @moduledoc """
  The single Consumer worker used to consume messages from a queue.
  """

  use AMQP
  use GenServer

  require Logger

  @opts ~w(connection consume_cb queue prefetch_count)a

  @this_module __MODULE__

  defmodule State do
    @moduledoc """
    The internal state held in the `RabbitMQ.Consumer.Worker` server.

    * `:channel`; holds the dedicated `AMQP.Channel`
    * `:consume_cb`; the callback invoked for each message consumed
    * `:consumer_tag`; the unique consumer identifier
    """

    @enforce_keys ~w(channel consume_cb consumer_tag)a
    defstruct @enforce_keys
  end

  ##############
  # Public API #
  ##############

  @doc """
  Starts this module as a process via `GenServer.start_link/2`.

  Should always be started via `Supervisor`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.take(opts, @opts)
    GenServer.start_link(@this_module, opts)
  end

  ######################
  # Callback Functions #
  ######################

  @impl true
  def init(opts) do
    # This is needed to invoke `terminate/2` when the parent process,
    # ideally a `Supervisor`, sends an exit signal.
    #
    # Read more @ https://hexdocs.pm/elixir/GenServer.html#c:terminate/2.
    Process.flag(:trap_exit, true)

    connection = Keyword.fetch!(opts, :connection)
    consume_cb = Keyword.fetch!(opts, :consume_cb)
    queue = Keyword.fetch!(opts, :queue)
    prefetch_count = Keyword.fetch!(opts, :prefetch_count)

    %Connection{} = connection = GenServer.call(connection, :get)

    with {:ok, channel} <- Channel.open(connection),
         {:ok, queue} <- declare_queue_if_exclusive(queue, channel),
         :ok <- Basic.qos(channel, prefetch_count: prefetch_count),
         {:ok, consumer_tag} <- Basic.consume(channel, queue) do
      # Monitor the channel process. Should channel exceptions occur,
      # such as when publishing to a non-existent exchange, we will
      # try to exit cleanly and let the supervisor restart the process.
      _ref = Process.monitor(channel.pid)

      {:ok, %State{channel: channel, consume_cb: consume_cb, consumer_tag: consumer_tag}}
    end
  end

  @impl true
  def handle_info(
        {:basic_consume_ok, %{consumer_tag: consumer_tag}},
        %State{} = state
      ) do
    Logger.debug("Consumer successfully registered as #{consumer_tag}.")
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:basic_cancel_ok, %{consumer_tag: consumer_tag}},
        %State{} = state
      ) do
    Logger.debug("Consumer #{consumer_tag} cancelled.")
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:basic_cancel, %{consumer_tag: consumer_tag}},
        %State{} = state
      ) do
    Logger.warn("Consumer #{consumer_tag} cancelled by broker.")
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:basic_deliver, payload, meta},
        %State{channel: %Channel{} = channel, consume_cb: consume_cb} = state
      ) do
    spawn(fn -> consume_cb.(payload, meta, channel) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _reference, :process, _pid, reason}, %State{} = state) do
    Logger.warn("Worker channel process down; #{inspect(reason)}.")
    # Stop GenServer; will be restarted by Supervisor.
    {:stop, {:channel_down, reason}, state}
  end

  @doc """
  Invoked when the server is about to exit. It should do any cleanup required.
  See https://hexdocs.pm/elixir/GenServer.html#c:terminate/2 for more details.
  """
  @impl true
  def terminate(reason, %State{channel: %Channel{} = channel, consumer_tag: consumer_tag} = state) do
    Logger.warn("Terminating Consumer Worker: #{inspect(reason)}. Cancelling consumer.")

    # Not sure this check is needed.
    if Process.alive?(channel.pid) do
      Basic.cancel(channel, consumer_tag)
      Channel.close(channel)
    end

    {:noreply, %{state | channel: nil}}
  end

  #####################
  # Private Functions #
  #####################

  defp declare_queue_if_exclusive({exchange, routing_key, queue_name, opts}, channel)
       when is_binary(queue_name) and is_list(opts),
       do: declare_exclusive_queue({exchange, routing_key, queue_name, opts}, channel)

  defp declare_queue_if_exclusive({exchange, routing_key, queue_name}, channel)
       when is_binary(queue_name),
       do: declare_exclusive_queue({exchange, routing_key, queue_name, []}, channel)

  defp declare_queue_if_exclusive({exchange, routing_key, opts}, channel)
       when is_list(opts),
       do: declare_exclusive_queue({exchange, routing_key, "", opts}, channel)

  defp declare_queue_if_exclusive({exchange, routing_key}, channel),
    do: declare_exclusive_queue({exchange, routing_key, "", []}, channel)

  defp declare_queue_if_exclusive(queue, _channel) when is_binary(queue), do: {:ok, queue}

  defp declare_exclusive_queue({exchange, routing_key, queue_name, opts}, channel) do
    opts = Keyword.put(opts, :exclusive, true)

    with {:ok, %{queue: queue}} <- Queue.declare(channel, queue_name, opts),
         :ok <- Queue.bind(channel, queue, exchange, routing_key: routing_key) do
      {:ok, queue}
    end
  end
end
