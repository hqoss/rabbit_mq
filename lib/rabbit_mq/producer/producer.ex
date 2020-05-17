defmodule RabbitMQ.Producer do
  @moduledoc """
  This module should be `use`d to start a Producer.

  Behind the scenes, a dedicated `AMQP.Connection` is established,
  and a pool of Producers (workers) is started, resulting in a supervision
  tree similar to the one below.

  ![Producer supervision tree](assets/producer-supervision-tree.png)

  ## Example usage

  ℹ️ The following example assumes that the `"customer"` exchange already exists.

  First, define your (ideally domain-specific) Producer:

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

          publish(payload, "customer.created", opts)
        end

        @doc \"\"\"
        Publishes an event routed via "customer.updated".
        \"\"\"
        def customer_updated(updated_customer) when is_map(updated_customer) do
          opts = [
            content_type: "application/json",
            correlation_id: UUID.uuid4()
          ]

          payload = Jason.encode!(%{v: "1.0.0", customer_data: updated_customer})

          publish(payload, "customer.updated", opts)
        end
      end

  ℹ️ To see which options can be passed as `opts` to `publish/3`,
  visit https://hexdocs.pm/amqp/AMQP.Basic.html#publish/5.

  Then, start as normal under your existing supervision tree:

      children = [
        RabbitSample.CustomerProducer
        # ... start other children
      ]

      opts = [strategy: :one_for_one, name: RabbitSample.Supervisor]
      Supervisor.start_link(children, opts)

  Finally, call the exposed methods from your application:

      RabbitSample.CustomerProducer.customer_created(customer_id)
      RabbitSample.CustomerProducer.customer_updated(updated_customer)

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
  * `:worker_count`; number of workers to be spawned. Defaults to `3`.
  """
  defmacro __using__(opts) do
    quote do
      alias RabbitMQ.Producer, as: Producer

      @behaviour Producer

      @connection __MODULE__.Connection
      @counter __MODULE__.Counter
      @name __MODULE__
      @worker_pool __MODULE__.WorkerPool
      @worker __MODULE__.Worker

      @exchange Keyword.fetch!(unquote(opts), :exchange)
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
          counter: @counter,
          exchange: @exchange,
          name: @name,
          worker: @worker,
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
        Producer.dispatch({routing_key, data, opts}, @counter, @worker, @worker_count)
      end
    end
  end

  alias AMQP.Basic
  alias RabbitMQ.Connection
  alias RabbitMQ.Producer.WorkerPool

  use Supervisor

  require Logger

  @this_module __MODULE__

  @supervisor_opts ~w(connection counter exchange name worker worker_count worker_pool)a
  @offset_key :offset
  @reset_counter_threshold 100_000

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
    name = Keyword.fetch!(opts, :name)
    supervisor_opts = Keyword.take(opts, @supervisor_opts)

    Supervisor.start_link(@this_module, supervisor_opts, name: name)
  end

  @doc """
  Sends a `:publish` message to a worker. Implements round-robin dispatch mechanism.
  """
  @spec dispatch(publish_args(), module(), module(), integer()) :: publish_result()
  def dispatch({routing_key, data, opts}, counter, worker, worker_count) do
    next = :ets.update_counter(counter, @offset_key, 1)

    # Reset the counter once it's above the threshold to prevent
    # performance degradation over time, e.g. when using `rem/2`.
    if next > @reset_counter_threshold do
      _reset = :ets.update_counter(counter, @offset_key, -next)
    end

    # Round-robin dispatch using the module name seems
    # to be the fastest and least intrusive way.
    index = rem(next, worker_count)
    worker = Module.concat(worker, "#{index}")

    GenServer.call(worker, {:publish, routing_key, data, opts})
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
  def init(supervisor_opts) do
    connection = Keyword.fetch!(supervisor_opts, :connection)
    counter = Keyword.fetch!(supervisor_opts, :counter)
    exchange = Keyword.fetch!(supervisor_opts, :exchange)
    name = Keyword.fetch!(supervisor_opts, :name)
    worker_count = Keyword.fetch!(supervisor_opts, :worker_count)
    worker = Keyword.fetch!(supervisor_opts, :worker)
    worker_pool = Keyword.fetch!(supervisor_opts, :worker_pool)

    handle_publisher_ack_confirms =
      get_publisher_confirm_callback(name, :handle_publisher_ack_confirms)

    handle_publisher_nack_confirms =
      get_publisher_confirm_callback(name, :handle_publisher_nack_confirms)

    # _ = :ets.new(ets_counter, [:named_table, :public, write_concurrency: true, read_concurrency: true])

    # No need for write or read concurrency as we are not using
    # this table to write or read more than one key.
    _ = :ets.new(counter, [:named_table, :public])
    _ = :ets.insert(counter, {@offset_key, -1})

    connection_opts = [max_channels: worker_count, name: connection]

    worker_pool_opts = [
      connection: connection,
      exchange: exchange,
      handle_publisher_ack_confirms: handle_publisher_ack_confirms,
      handle_publisher_nack_confirms: handle_publisher_nack_confirms,
      name: worker_pool,
      worker: worker,
      worker_count: worker_count
    ]

    children = [
      %{
        id: :connection,
        start: {Connection, :start_link, [connection_opts]}
      },
      %{
        id: :worker_pool,
        start: {WorkerPool, :start_link, [worker_pool_opts]},
        type: :supervisor
      }
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp get_publisher_confirm_callback(module, :handle_publisher_ack_confirms = fun) do
    case function_exported?(module, fun, 1) do
      true -> fn events -> apply(module, fun, [events]) end
      false -> &handle_acks/1
    end
  end

  defp get_publisher_confirm_callback(module, :handle_publisher_nack_confirms = fun) do
    case function_exported?(module, fun, 1) do
      true -> fn events -> apply(module, fun, [events]) end
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
