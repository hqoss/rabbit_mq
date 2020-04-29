defmodule RabbitMQ.Consumer.Worker do
  alias AMQP.{Basic, Channel}

  require Logger

  use GenServer

  @this_module __MODULE__

  defmodule Config do
    @enforce_keys ~w(connection consume_cb queue prefetch_count)a
    defstruct @enforce_keys
  end

  defmodule State do
    @enforce_keys ~w(channel config consumer_tag)a
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
  def init(%Config{connection: connection, queue: queue, prefetch_count: prefetch_count} = config) do
    # Notify when an exit happens, be it graceful or forceful.
    # The corresponding channel and the consumer will both be closed.
    Process.flag(:trap_exit, true)

    with {:ok, channel} <- Channel.open(connection),
         :ok <- Basic.qos(channel, prefetch_count: prefetch_count),
         {:ok, consumer_tag} <- Basic.consume(channel, queue) do
      {:ok, %State{channel: channel, config: config, consumer_tag: consumer_tag}}
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
        {:basic_deliver, payload, meta},
        %State{channel: %Channel{} = channel, config: %Config{consume_cb: consume_cb}} = state
      ) do
    spawn(fn -> consume_cb.(payload, meta, channel) end)
    {:noreply, state}
  end

  @impl true
  def terminate(reason, %State{channel: %Channel{} = channel, consumer_tag: consumer_tag} = state) do
    Logger.warn(
      "Terminating Consumer Worker due to #{inspect(reason)}. Closing dedicated channel."
    )

    Basic.cancel(channel, consumer_tag)
    Channel.close(channel)

    {:noreply, %{state | channel: nil}}
  end
end
