defmodule RabbitMQ.Consumer do
  @moduledoc """
  This module can be `use`d to start and maintain a pool of Consumer workers.

  ## Example usage

  `rabbit_mq` allows you to design consistent, SDK-like Consumers.

  ℹ️ The following example assumes that the `"customer/customer.updated"` queue already exists.

  First, define your Consumer(s):

      defmodule RabbitSample.CustomerCreatedConsumer do
        use RabbitMQ.Consumer, queue: "customer/customer.created", worker_count: 2, prefetch_count: 3

        require Logger

        def consume(payload, meta, channel) do
          Logger.info("Customer #{payload} created.")
          ack(channel, meta.delivery_tag)
        end
      end

      defmodule RabbitSample.CustomerUpdatedConsumer do
        use RabbitMQ.Consumer, queue: "customer/customer.updated", worker_count: 2, prefetch_count: 6

        require Logger

        def consume(payload, meta, channel) do
          Logger.info("Customer updated. Data: #{payload}.")
          ack(channel, meta.delivery_tag)
        end
      end

  Then, start as normal under your existing supervision tree:

      children = [
        RabbitSample.Topology,
        RabbitSample.CustomerProducer,
        RabbitSample.CustomerCreatedConsumer,
        RabbitSample.CustomerUpdatedConsumer
      ]

      opts = [strategy: :one_for_one, name: RabbitSample.Supervisor]
      Supervisor.start_link(children, opts)

  As messages are published onto the `"customer/customer.created"`, or `"customer/customer.updated"` queues,
  the corresponding `consume/3` will be invoked.

  ⚠️ Please note that automatic message acknowledgement is **disabled** in `rabbit_mq`, therefore
  it's _your_ responsibility to ensure messages are `ack`'d or `nack`'d.

  ℹ️ Please consult the
  [Consumer Acknowledgement Modes and Data Safety Considerations](https://www.rabbitmq.com/confirms.html#acknowledgement-modes)
  for more details.

  ## Configuration

  The following options can be used with `RabbitMQ.Consumer`;

  * `:prefetch_count`;
      limits the number of unacknowledged messages on a channel.
      Please consult the
      [Consumer Prefetch](https://www.rabbitmq.com/consumer-prefetch.html)
      section for more details.
      Defaults to `10`.
  * `:queue`;
      the name of the queue from which the Consumer should start consuming.
      **For exclusive queues, please see the Exclusive Queues section further below.**
      **Required**.
  * `:worker_count`;
      number of workers to be spawned.
      Cannot be greater than `:max_channels_per_connection` set in config.
      Defaults to `3`.

  When you `use RabbitMQ.Consumer`, a few things happen;

  1. The module turns into a `GenServer`.
  2. The server starts _and supervises_ the desired number of workers.
  3. `consume/3` is passed as a callback to each worker when `start_link/1` is called.
  4. _If_ an exclusive queue is requested, it will be declared and bound to the Consumer.
  5. Each worker starts consuming from the queue provided, calls `consume/3` for each message consumed.
  6. `ack/2`, `nack/2`, and `reject/2` become automatically available.

  `consume/3` needs to be defined with the following signature;

      @type payload :: String.t()
      @type meta :: map()
      @type channel :: AMQP.Channel.t()
      @type result :: :ok | {:error, :retry} | {:error, term()}

      consume(payload(), meta(), channel()) :: result()

  ### Exclusive queues

  If you want to consume from an exclusive queue, simply use one of the following tuples in the configuration;

  * `{exchange, routing_key}`
  * `{exchange, routing_key, opts}`
  * `{exchange, routing_key, queue_name}`
  * `{exchange, routing_key, queue_name, opts}`

  ℹ️ At a minimum, the `exchange` and the `routing_key` are required.

      defmodule CustomerConsumer do
        use RabbitMQ.Consumer, queue: {"customer", "customer.*"}, worker_count: 3

        # Define `consume/3` as normal.
      end

  This will ensure that the queue is declared and correctly bound before the Consumer workers start
  consuming messages off it.
  """

  defmacro __using__(opts) do
    quote do
      alias AMQP.{Basic, Channel}
      alias RabbitMQ.Consumer

      require Logger

      @prefetch_count unquote(Keyword.get(opts, :prefetch_count, 10))
      @queue unquote(Keyword.fetch!(opts, :queue))
      @worker_count unquote(Keyword.get(opts, :worker_count, 3))
      @max_workers Application.compile_env(:rabbit_mq, :max_channels_per_connection, 8)
      @this_module __MODULE__

      if @worker_count > @max_workers do
        raise """
        Cannot start #{@worker_count} workers, maximum channels per connection is #{@max_workers}.

        You can configure this value as shown below;

          config :rabbit_mq, max_channels_per_connection: 16

        As a rule of thumb, most applications can use a single digit number of channels per connection.

        For details, please consult the official RabbitMQ docs: https://www.rabbitmq.com/channels.html#channel-max.
        """
      end

      @callback consume(String.t(), map(), Channel.t()) :: term()

      ##############
      # Public API #
      ##############

      def child_spec(opts) do
        config = %{
          consume_cb: &consume/3,
          prefetch_count: @prefetch_count,
          queue: @queue,
          worker_count: @worker_count
        }

        opts = Keyword.put_new(opts, :name, @this_module)

        # Read more about child specification:
        # https://hexdocs.pm/elixir/Supervisor.html#module-child-specification
        %{
          id: @this_module,
          start: {Consumer, :start_link, [config, opts]},
          type: :supervisor,
          # Read more about restart values:
          # https://hexdocs.pm/elixir/Supervisor.html#module-restart-values-restart
          restart: :permanent,
          # Read more about shutdown values:
          # https://hexdocs.pm/elixir/Supervisor.html#module-shutdown-values-shutdown
          shutdown: :brutal_kill
        }
      end

      ###########################
      # Useful Helper Functions #
      ###########################

      defdelegate ack(channel, tag), to: Basic
      defdelegate nack(channel, tag), to: Basic
      defdelegate reject(channel, tag), to: Basic
    end
  end

  alias AMQP.{Channel, Connection, Queue}
  alias RabbitMQ.Consumer.Worker

  require Logger

  use GenServer

  @this_module __MODULE__

  defmodule State do
    @moduledoc """
    The internal state held in the `RabbitMQ.Consumer` server.

    * `:connection`;
        holds the dedicated `AMQP.Connection`.
    * `:workers`;
        the children started under the server. The server acts as a `Supervisor`.
    """

    @enforce_keys [:connection, :workers]
    defstruct connection: nil, workers: []
  end

  ##############
  # Public API #
  ##############

  @doc """
  Starts this module as a process via `GenServer.start_link/3`.

  Only used by the module's `child_spec`.
  """
  def start_link(init_arg, opts) do
    GenServer.start_link(@this_module, init_arg, opts)
  end

  ######################
  # Callback Functions #
  ######################

  @impl true
  def init(config) do
    Process.flag(:trap_exit, true)

    # Each worker pool will maintain and monitor its own connection.
    {:ok, connection} = connect()

    {:ok, queue} = declare_queue_if_exclusive(config.queue, connection)

    config = Map.replace!(config, :queue, queue)

    workers =
      1..config.worker_count
      |> Enum.with_index()
      |> Enum.map(fn {_, index} -> start_worker(index, config, connection) end)

    {:ok, %State{connection: connection, workers: workers}}
  end

  @impl true
  def handle_info({:DOWN, _, :process, _pid, reason}, %State{} = state) do
    Logger.warn("Connection to broker lost due to #{inspect(reason)}.")

    # Stop GenServer; will be restarted by Supervisor. Linked processes will be terminated,
    # and all channels implicitly closed due to the connection process being down.
    {:stop, {:connection_lost, reason}, %{state | connection: nil}}
  end

  @impl true
  def handle_info(
        {:EXIT, from, reason},
        %State{connection: connection, workers: workers} = state
      ) do
    Logger.warn("Consumer worker process terminated due to #{inspect(reason)}. Restarting.")

    {index, _old_pid, config} = Enum.find(workers, fn {_index, pid, _config} -> pid === from end)

    # Clean up, new channel will be established in `start_worker/3`.
    :ok = Channel.close(config.channel)

    updated_workers = List.replace_at(workers, index, start_worker(index, config, connection))

    {:noreply, %{state | workers: updated_workers}}
  end

  @doc """
  Invoked when the server is about to exit. It should do any cleanup required.
  See https://hexdocs.pm/elixir/GenServer.html#c:terminate/2 for more details.
  """
  @impl true
  def terminate(reason, %State{connection: connection} = state) do
    Logger.warn("Terminating Producer pool: #{inspect(reason)}. Closing connection.")

    case connection do
      %Connection{} -> Connection.close(connection)
      nil -> :ok
    end

    {:noreply, %{state | connection: nil}}
  end

  #####################
  # Private Functions #
  #####################

  defp connect do
    opts = [channel_max: max_channels(), heartbeat: heartbeat_interval_sec()]

    amqp_url()
    |> Connection.open(opts)
    |> case do
      {:ok, connection} ->
        # Get notifications when the connection goes down
        Process.monitor(connection.pid)
        {:ok, connection}

      {:error, error} ->
        Logger.error("Failed to connect to broker due to #{inspect(error)}. Retrying...")
        :timer.sleep(reconnect_interval_ms())
        connect()
    end
  end

  defp declare_queue_if_exclusive({exchange, routing_key, queue_name, opts}, connection)
       when is_binary(queue_name) and is_list(opts),
       do: declare_queue({exchange, routing_key, queue_name, opts}, connection)

  defp declare_queue_if_exclusive({exchange, routing_key, queue_name}, connection)
       when is_binary(queue_name),
       do: declare_queue({exchange, routing_key, queue_name, []}, connection)

  defp declare_queue_if_exclusive({exchange, routing_key, opts}, connection)
       when is_list(opts),
       do: declare_queue({exchange, routing_key, "", opts}, connection)

  defp declare_queue_if_exclusive({exchange, routing_key}, connection),
    do: declare_queue({exchange, routing_key, "", []}, connection)

  defp declare_queue_if_exclusive(queue, _connection) when is_binary(queue), do: {:ok, queue}

  defp declare_queue({exchange, routing_key, queue_name, opts}, connection) do
    {:ok, channel} = Channel.open(connection)
    opts = Keyword.put(opts, :exclusive, true)
    {:ok, %{queue: queue_name}} = Queue.declare(channel, queue_name, opts)
    :ok = Queue.bind(channel, queue_name, exchange, routing_key: routing_key)
    :ok = Channel.close(channel)
    {:ok, queue_name}
  end

  defp start_worker(index, config, connection) do
    {:ok, channel} = Channel.open(connection)

    config =
      config
      |> Map.put(:channel, channel)
      |> Map.take(~w(channel consume_cb prefetch_count queue)a)

    {:ok, pid} = Worker.start_link(config)

    {index, pid, config}
  end

  defp amqp_url, do: Application.fetch_env!(:rabbit_mq, :amqp_url)
  defp heartbeat_interval_sec, do: Application.get_env(:rabbit_mq, :heartbeat_interval_sec, 30)
  defp reconnect_interval_ms, do: Application.get_env(:rabbit_mq, :reconnect_interval_ms, 2500)
  defp max_channels, do: Application.get_env(:rabbit_mq, :max_channels_per_connection, 8)
end
