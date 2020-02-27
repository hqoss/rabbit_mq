defmodule RabbitMQ.Producer.Worker do
  alias AMQP.{Basic, Channel, Confirm}

  require Logger

  use GenServer

  @this_module __MODULE__

  defmodule Config do
    @enforce_keys ~w(channel_type connection confirm_timeout)a
    defstruct @enforce_keys
  end

  defmodule State do
    @enforce_keys ~w(channel config)a
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
  def init(%Config{channel_type: :confirm, connection: connection} = config) do
    with {:ok, channel} <- Channel.open(connection),
         :ok <- Confirm.select(channel) do
      {:ok, %State{config: config, channel: channel}}
    end
  end

  @impl true
  def init(%Config{connection: connection} = config) do
    with {:ok, channel} <- Channel.open(connection) do
      {:ok, %State{config: config, channel: channel}}
    end
  end

  @impl true
  def handle_call(
        {:publish, exchange, routing_key, data, opts},
        _from,
        %State{
          config: %Config{channel_type: :confirm, confirm_timeout: confirm_timeout},
          channel: %Channel{} = channel
        } = state
      ) do
    case do_publish(channel, exchange, routing_key, data, opts) do
      :ok ->
        true = Confirm.wait_for_confirms_or_die(channel, confirm_timeout)
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(
        {:publish, exchange, routing_key, data, opts},
        _from,
        %State{
          channel: %Channel{} = channel
        } = state
      ) do
    case do_publish(channel, exchange, routing_key, data, opts) do
      :ok -> {:reply, {:ok, channel}, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def terminate(reason, %State{channel: %Channel{} = channel} = state) do
    Logger.warn(
      "Terminating Producer Worker due to #{inspect(reason)}. Closing dedicated channel."
    )

    Channel.close(channel)

    {:noreply, %{state | channel: nil}}
  end

  #####################
  # Private Functions #
  #####################

  defp do_publish(channel, exchange, routing_key, data, opts) do
    if Keyword.has_key?(opts, :correlation_id) do
      Basic.publish(channel, exchange, routing_key, data, opts)
    else
      {:error, :correlation_id_missing}
    end
  end
end
