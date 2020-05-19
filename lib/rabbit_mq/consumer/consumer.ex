defmodule RabbitMQ.Consumer do
  @moduledoc """
  This module can be `use`d to start and maintain a pool of Consumer workers.

  ## Example usage

  `rabbit_mq` allows you to design consistent, SDK-like Consumers.

  ℹ️ The following example assumes that the `"customer/customer.updated"` queue already exists.

  First, define your Consumer(s).

  To consume off `"customer/customer.created"`:

      defmodule RabbitSample.CustomerCreatedConsumer do
        use RabbitMQ.Consumer, queue: "customer/customer.created", worker_count: 2, prefetch_count: 3

        require Logger

        def handle_message(payload, meta, channel) do
          Logger.info("Customer \#{payload} created.")
          ack(channel, meta.delivery_tag)
        end
      end

  To consume off `"customer/customer.updated"`:

      defmodule RabbitSample.CustomerUpdatedConsumer do
        use RabbitMQ.Consumer, queue: "customer/customer.updated", worker_count: 2, prefetch_count: 6

        require Logger

        def handle_message(payload, meta, channel) do
          Logger.info("Customer updated. Data: \#{payload}.")
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
  the corresponding `handle_message/3` will be invoked.

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
  3. `handle_message/3` is passed as a callback to each worker when `start_link/1` is called.
  4. _If_ an exclusive queue is requested, it will be declared and bound to the Consumer.
  5. Each worker starts consuming from the queue provided, calls `handle_message/3` for each message consumed.
  6. `ack/2`, `ack/3`, `nack/2`, `nack/3`, `reject/2`, and `reject/3` become automatically available.

  `handle_message/3` needs to be defined with the following signature;

      @type payload :: String.t()
      @type meta :: map()
      @type channel :: AMQP.Channel.t()
      @type result :: term()

      @callback handle_message(payload(), meta(), channel()) :: result()

  ### Exclusive queues

  If you want to consume from an exclusive queue, simply use one of the following tuples in the configuration;

  * `{exchange, routing_key}`
  * `{exchange, routing_key, opts}`
  * `{exchange, routing_key, queue_name}`
  * `{exchange, routing_key, queue_name, opts}`

  ℹ️ At a minimum, the `exchange` and the `routing_key` are required.

      defmodule CustomerConsumer do
        use RabbitMQ.Consumer, queue: {"customer", "customer.*"}, worker_count: 3

        # Define `handle_message/3` as normal.
      end

  This will ensure that the queue is declared and correctly bound before the Consumer workers start
  consuming messages off it.
  """

  defmacro __using__(opts) do
    quote do
      alias RabbitMQ.Consumer

      import AMQP.Basic, only: [ack: 2, ack: 3, nack: 2, nack: 3, reject: 2, reject: 3]

      @behaviour Consumer

      @connection __MODULE__.Connection
      @name __MODULE__
      @worker_pool __MODULE__.WorkerPool

      @queue Keyword.fetch!(unquote(opts), :queue)
      @prefetch_count Keyword.get(unquote(opts), :prefetch_count, 10)
      @worker_count Keyword.get(unquote(opts), :worker_count, 3)

      @doc """
      Calls `RabbitMQ.Consumer.child_spec/1` with scoped `opts`.
      """
      def child_spec(_) do
        max_workers = Consumer.max_workers()

        if @worker_count > max_workers do
          raise """
          Cannot start #{@worker_count} workers, maximum is #{max_workers}.

          You can configure this value as shown below;

            config :rabbit_mq, max_channels_per_connection: 16

          As a rule of thumb, most applications can use a single digit number of channels per connection.

          For details, please consult the official RabbitMQ docs: https://www.rabbitmq.com/channels.html#channel-max.
          """
        end

        opts = [
          connection: @connection,
          consume_cb: &handle_message/3,
          name: @name,
          queue: @queue,
          prefetch_count: @prefetch_count,
          worker_count: @worker_count,
          worker_pool: @worker_pool
        ]

        Supervisor.child_spec({Consumer, opts}, id: @name)
      end
    end
  end

  alias RabbitMQ.Connection, as: DedicatedConnection
  alias RabbitMQ.Consumer.Worker

  use AMQP
  use Supervisor

  require Logger

  @this_module __MODULE__

  @opts ~w(connection consume_cb exchange name queue prefetch_count worker_count worker_pool)a

  @type payload :: String.t()
  @type meta :: map()
  @type channel :: Channel.t()

  @callback handle_message(payload(), meta(), channel()) :: term()

  @doc """
  Starts a named `Supervisor`, internally managing a dedicated
  `AMQP.Connection` as well a dedicated `RabbitMQ.Consumer.WorkerPool`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.take(opts, @opts)
    name = Keyword.fetch!(opts, :name)

    Supervisor.start_link(@this_module, opts, name: name)
  end

  @doc """
  Retrieves the application-level limit on how many channels
  can be opened per connection. Can be configured via
  `:rabbit_mq, :max_channels_per_connection`.

  If not set in config, defaults to `8`.

  As a rule of thumb, most applications can use a single digit number of channels per connection.

  For details, please consult the official RabbitMQ docs: https://www.rabbitmq.com/channels.html#channel-max.
  """
  @spec max_workers() :: integer()
  def max_workers, do: Application.get_env(:rabbit_mq, :max_channels_per_connection, 8)

  ######################
  # Callback Functions #
  ######################

  @impl true
  def init(opts) do
    connection = Keyword.fetch!(opts, :connection)
    consume_cb = Keyword.fetch!(opts, :consume_cb)
    queue = Keyword.fetch!(opts, :queue)
    prefetch_count = Keyword.fetch!(opts, :prefetch_count)
    worker_count = Keyword.fetch!(opts, :worker_count)
    worker_pool = Keyword.fetch!(opts, :worker_pool)

    connection_opts = [max_channels: worker_count, name: connection]

    worker_pool_opts = [
      name: {:local, worker_pool},
      worker_module: Worker,
      size: worker_count,
      max_overflow: 0
    ]

    worker_opts = [
      connection: connection,
      consume_cb: consume_cb,
      queue: queue,
      prefetch_count: prefetch_count
    ]

    children = [
      %{
        id: :connection,
        start: {DedicatedConnection, :start_link, [connection_opts]}
      },
      %{
        id: :worker_pool,
        start: {:poolboy, :start_link, [worker_pool_opts, worker_opts]},
        type: :supervisor
      }
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
