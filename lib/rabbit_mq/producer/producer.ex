defmodule RabbitMQ.Producer do
  @moduledoc """
  This module should be `use`d to start a Producer.

  ## Example usage

  ℹ️ The following example assumes that the `"customer"` exchange already exists.

      defmodule RabbitSample.CustomerProducer do
        @moduledoc \"\"\"
        Publishes pre-configured events onto the "customer" exchange.
        \"\"\"

        use RabbitMQ.Producer, exchange: "customer", worker_count: 3

        @doc \"\"\"
        Publishes an event routed via "customer.created".
        \"\"\"
        def customer_created(customer_id) when is_binary(customer_id) do
          opts = [
            content_type: "application/json",
            correlation_id: UUID.uuid4()
          ]

          payload = Jason.encode!(%{v: "1.0.0", customer_id: customer_id})

          publish("customer.created", payload, opts)
        end
      end

  Behind the scenes, a dedicated `AMQP.Connection` is established,
  and a pool of `RabbitMQ.Producer.Worker`s is started, resulting in a supervision
  tree similar to the one below.

  ![Producer supervision tree](assets/producer-supervision-tree.png)

  ℹ️ To see which options can be passed as `opts` to `publish/3`,
  visit https://hexdocs.pm/amqp/AMQP.Basic.html#publish/5.

  Start under your existing supervision tree as normal:

      children = [
        RabbitSample.CustomerProducer
        # ... start other children
      ]

      opts = [strategy: :one_for_one, name: RabbitSample.Supervisor]
      Supervisor.start_link(children, opts)

  Call the exposed methods from your application:

      RabbitSample.CustomerProducer.customer_created(customer_id)

  ⚠️ All Producer workers implement "reliable publishing", which means that
  publisher confirms are always enabled and handled _asynchronously_, striking
  a delicate balance between performance and reliability.

  To understand why this is important, please refer to the
  [reliable publishing implementation guide](https://www.rabbitmq.com/tutorials/tutorial-seven-java.html).

  You can implement the _optional_ `handle_publisher_ack_confirms/1` and
  `handle_publisher_nack_confirms/1` callbacks to receive publisher confirmations.

  ## Configuration

  The following options can be used with `RabbitMQ.Producer`;

  * `:exchange`; messages will be published onto this exchange. **Required**.
  * `:max_overflow`; temporarily add workers if needed. Defaults to `0`.
  * `:publish_timeout`; when reached, the pool will not accept any new requests until the next process finishes. Defaults to `500`.
  * `:worker_count`; number of workers to be spawned. Defaults to `3`.
  """
  defmacro __using__(opts) do
    quote do
      alias RabbitMQ.Producer, as: Producer

      @behaviour Producer

      @connection __MODULE__.Connection
      @name __MODULE__
      @worker_pool __MODULE__.WorkerPool

      @exchange Keyword.fetch!(unquote(opts), :exchange)
      @max_overflow Keyword.get(unquote(opts), :max_overflow, 0)
      @publish_timeout Keyword.get(unquote(opts), :publish_timeout, 500)
      @worker_count Keyword.get(unquote(opts), :worker_count, 3)

      @doc """
      Calls `RabbitMQ.Producer.child_spec/1` with scoped `opts`.
      """
      def child_spec(_) do
        max_workers = Producer.max_workers()

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
          exchange: @exchange,
          max_overflow: @max_overflow,
          name: @name,
          worker_count: @worker_count,
          worker_pool: @worker_pool
        ]

        Supervisor.child_spec({Producer, opts}, id: @name)
      end

      @doc """
      Dispatches a message to a worker in order to perform a publish.
      """
      @impl true
      def publish(routing_key, data, opts)
          when is_binary(routing_key) and is_binary(data) and is_list(opts) do
        Producer.publish({routing_key, data, opts}, @worker_pool, @publish_timeout)
      end
    end
  end

  use AMQP
  alias RabbitMQ.Connection, as: DedicatedConnection
  alias RabbitMQ.Producer.Worker

  use Supervisor

  require Logger

  @this_module __MODULE__

  @opts ~w(connection exchange max_overflow name worker_count worker_pool)a

  @type seq_no :: integer()
  @type routing_key :: String.t()
  @type data :: String.t()
  @type opts :: keyword()
  @type publish_args_with_seq_no :: {seq_no(), routing_key(), data(), opts()}

  @type publish_args :: {routing_key(), data(), opts()}
  @type publish_result :: {:ok, integer()} | Basic.error()

  @callback publish(routing_key(), data(), opts()) :: publish_result()
  @callback handle_publisher_ack_confirms(list(publish_args_with_seq_no())) :: term()
  @callback handle_publisher_nack_confirms(list(publish_args_with_seq_no())) :: term()

  @optional_callbacks handle_publisher_ack_confirms: 1, handle_publisher_nack_confirms: 1

  @doc """
  Starts a named `Supervisor`, internally managing a dedicated
  `AMQP.Connection` as well a dedicated `RabbitMQ.Producer.WorkerPool`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.take(opts, @opts)
    name = Keyword.fetch!(opts, :name)

    Supervisor.start_link(@this_module, opts, name: name)
  end

  @spec publish(publish_args(), module(), integer()) :: publish_result()
  def publish({routing_key, data, opts}, worker_pool, publish_timeout) do
    :poolboy.transaction(
      worker_pool,
      fn pid -> GenServer.call(pid, {:publish, routing_key, data, opts}) end,
      publish_timeout
    )
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
    exchange = Keyword.fetch!(opts, :exchange)
    max_overflow = Keyword.fetch!(opts, :max_overflow)
    name = Keyword.fetch!(opts, :name)
    worker_count = Keyword.fetch!(opts, :worker_count)
    worker_pool = Keyword.fetch!(opts, :worker_pool)

    handle_publisher_ack_confirms =
      get_publisher_confirm_callback(name, :handle_publisher_ack_confirms)

    handle_publisher_nack_confirms =
      get_publisher_confirm_callback(name, :handle_publisher_nack_confirms)

    connection_opts = [max_channels: worker_count, name: connection]

    worker_pool_opts = [
      name: {:local, worker_pool},
      worker_module: Worker,
      size: worker_count,
      max_overflow: max_overflow
    ]

    worker_opts = [
      connection: connection,
      exchange: exchange,
      handle_publisher_ack_confirms: handle_publisher_ack_confirms,
      handle_publisher_nack_confirms: handle_publisher_nack_confirms
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

  defp get_publisher_confirm_callback(module, :handle_publisher_ack_confirms = fun) do
    case function_exported?(module, fun, 1) do
      true -> fn events -> module.handle_publisher_ack_confirms(events) end
      false -> &handle_acks/1
    end
  end

  defp get_publisher_confirm_callback(module, :handle_publisher_nack_confirms = fun) do
    case function_exported?(module, fun, 1) do
      true -> fn events -> module.handle_publisher_nack_confirms(events) end
      false -> &handle_nacks/1
    end
  end

  defp handle_acks(events) do
    Enum.map(events, fn {seq_number, _routing_key, _data, _opts} ->
      Logger.debug("Publisher acknowledged #{seq_number}.")
    end)
  end

  defp handle_nacks(events) do
    Enum.map(events, fn {seq_number, _routing_key, _data, _opts} ->
      Logger.error("Publisher negatively acknowledged #{seq_number}.")
    end)
  end
end
