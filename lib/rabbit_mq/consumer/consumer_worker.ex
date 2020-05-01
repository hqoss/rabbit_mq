defmodule RabbitMQ.Consumer.Worker do
  @moduledoc """
  The single Consumer worker used to consume messages from a queue.

  Calls `consume/3` defined in the parent module for each message consumed.
  """

  alias AMQP.{Basic, Channel}

  require Logger

  use GenServer

  @this_module __MODULE__

  defmodule State do
    @moduledoc """
    The internal state held in the `RabbitMQ.Consumer.Worker` server.

    * `:channel`;
        holds the dedicated `AMQP.Channel`.
    * `:consume_cb`;
        the callback invoked for each message consumed.
    * `:consumer_tag`;
        the unique consumer identifier.
    """

    @enforce_keys ~w(channel consume_cb consumer_tag)a
    defstruct @enforce_keys
  end

  ##############
  # Public API #
  ##############

  def start_link(config) do
    GenServer.start_link(@this_module, config)
  end

  ######################
  # Callback Functions #
  ######################

  @impl true
  def init(%{
        channel: channel,
        consume_cb: consume_cb,
        queue: queue,
        prefetch_count: prefetch_count
      }) do
    # Notify when an exit happens, be it graceful or forceful.
    # The corresponding channel and the consumer will both be closed.
    Process.flag(:trap_exit, true)

    with :ok <- Basic.qos(channel, prefetch_count: prefetch_count),
         {:ok, consumer_tag} <- Basic.consume(channel, queue) do
      {:ok, %State{channel: channel, consume_cb: consume_cb, consumer_tag: consumer_tag}}
    end
  end

  @impl true
  def handle_info(
        {:basic_consume_ok, %{consumer_tag: consumer_tag}},
        %State{} = state
      ) do
    Logger.info("Consumer successfully registered as #{consumer_tag}.")
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:basic_cancel_ok, %{consumer_tag: consumer_tag}},
        %State{} = state
      ) do
    Logger.info("Consumer #{consumer_tag} cancelled.")
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

  @doc """
  Invoked when the server is about to exit. It should do any cleanup required.
  See https://hexdocs.pm/elixir/GenServer.html#c:terminate/2 for more details.
  """
  @impl true
  def terminate(reason, %State{channel: %Channel{} = channel, consumer_tag: consumer_tag} = state) do
    Logger.warn("Terminating Consumer Worker: #{inspect(reason)}. Unregistering consumer.")

    if Process.alive?(channel.pid) do
      # The channel itself is managed outside of this worker and as such
      # will be closed and re-established with by the parent process.
      Basic.cancel(channel, consumer_tag)
    end

    {:noreply, %{state | channel: nil}}
  end
end
