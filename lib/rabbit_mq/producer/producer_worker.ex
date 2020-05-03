defmodule RabbitMQ.Producer.Worker do
  @moduledoc """
  The single Producer worker used to publish messages onto an exchange.
  """

  alias AMQP.{Basic, Channel, Confirm}

  require Logger

  use GenServer

  @this_module __MODULE__

  defmodule State do
    @moduledoc """
    The internal state held in the `RabbitMQ.Producer.Worker` server.

    * `:channel`;
        holds the dedicated `AMQP.Channel`.
    * `:outstanding_confirms`;
        holds the reference to the protected ets table used to track outstanding Publisher `ack` or `nack` confirms.
    """

    @enforce_keys ~w(channel nack_cb outstanding_confirms)a
    defstruct @enforce_keys
  end

  ##############
  # Public API #
  ##############

  @doc """
  Starts this module as a process via `GenServer.start_link/2`.

  Only used by the parent module which acts as a `Supervisor`.
  """
  @spec start_link(map()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(@this_module, config)
  end

  ######################
  # Callback Functions #
  ######################

  @impl true
  def init(%{channel: channel, confirm_type: :async, nack_cb: nack_cb}) do
    # Notify when an exit happens, be it graceful or forceful.
    # The corresponding channel and async handler will both be closed.
    Process.flag(:trap_exit, true)

    with :ok <- Confirm.select(channel),
         :ok <- Confirm.register_handler(channel, self()) do
      {:ok, %State{channel: channel, nack_cb: nack_cb, outstanding_confirms: []}}
    end
  end

  @impl true
  def handle_call(
        {:publish, exchange, routing_key, data, opts},
        _from,
        %State{channel: %Channel{} = channel, outstanding_confirms: outstanding_confirms} = state
      ) do
    next_publish_seqno = Confirm.next_publish_seqno(channel)

    # TODO what happens if confirms are not received within a given time limit?
    # Are they nacked after a specific timeout? Is that configurable?
    case do_publish(channel, exchange, routing_key, data, opts) do
      :ok ->
        outstanding_confirms = [
          {next_publish_seqno, data, routing_key, opts} | outstanding_confirms
        ]

        {:reply, {:ok, next_publish_seqno}, %{state | outstanding_confirms: outstanding_confirms}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info(
        {confirmation_type, seq_number, false},
        %State{nack_cb: nack_cb, outstanding_confirms: outstanding_confirms} = state
      )
      when confirmation_type in [:basic_ack, :basic_nack] do
    Logger.debug("Received #{confirmation_type} of #{seq_number}.")

    {confirmed, outstanding} =
      case outstanding_confirms do
        [{^seq_number, _data, _routing_key, _opts} = confirmed] ->
          {[confirmed], []}

        [{^seq_number, _data, _routing_key, _opts} = confirmed | rest] ->
          {[confirmed], rest}

        list ->
          confirmed =
            Enum.find(list, fn
              {^seq_number, _data, _routing_key, _opts} -> true
              _ -> false
            end)

          {[confirmed], List.delete(list, confirmed)}
      end

    if confirmation_type === :basic_nack do
      nack_cb.(confirmed)
    end

    {:noreply, %{state | outstanding_confirms: outstanding}}
  end

  @impl true
  def handle_info(
        {confirmation_type, seq_number, true},
        %State{nack_cb: nack_cb, outstanding_confirms: outstanding_confirms} = state
      )
      when confirmation_type in [:basic_ack, :basic_nack] do
    Logger.debug("Received #{confirmation_type} up to #{seq_number}.")

    {confirmed, outstanding} =
      case outstanding_confirms do
        [{^seq_number, _data, _routing_key, _opts} | _outstanding] = confirmed ->
          {confirmed, []}

        list ->
          {outstanding, confirmed} =
            Enum.split_while(list, fn {seq_no, _data, _routing_key, _opts} ->
              seq_no < seq_number
            end)

          {confirmed, outstanding}
      end

    if confirmation_type === :basic_nack do
      nack_cb.(confirmed)
    end

    {:noreply, %{state | outstanding_confirms: outstanding}}
  end

  @doc """
  Invoked when the server is about to exit. It should do any cleanup required.
  See https://hexdocs.pm/elixir/GenServer.html#c:terminate/2 for more details.
  """
  @impl true
  def terminate(reason, %State{channel: %Channel{} = channel} = state) do
    Logger.warn("Terminating Producer Worker: #{inspect(reason)}. Unregistering handler.")

    if Process.alive?(channel.pid) do
      # The channel itself is managed outside of this worker and as such
      # will be closed and re-established by the parent process.
      Confirm.unregister_handler(channel)
    end

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
