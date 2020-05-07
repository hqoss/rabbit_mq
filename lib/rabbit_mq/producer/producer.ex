defmodule RabbitMQ.Producer do
  @moduledoc """
  This module can be `use`d to start and maintain a pool of Producer workers.

  ## Example usage

  `rabbit_mq` allows you to design consistent, SDK-like Producers.

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
            correlation_id: UUID.uuid4(),
            mandatory: true
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
            correlation_id: UUID.uuid4(),
            mandatory: true
          ]

          payload = Jason.encode!(%{v: "1.0.0", customer_data: updated_customer})

          publish(payload, "customer.updated", opts)
        end

        @doc \"\"\"
        In the unlikely event of a failed publisher confirm, messages that go
        unack'd will be passed onto this callback. You can use this to notify
        another process and deal with such exceptions in any way you like.
        \"\"\"
        def handle_publisher_nack(unackd_messages) do
          Logger.error("Failed to publish messages: \#{inspect(unackd_messages)}")
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

  Finally, call the exposed methods from your application:

      RabbitSample.CustomerProducer.customer_created(customer_id)
      RabbitSample.CustomerProducer.customer_updated(updated_customer)


  ⚠️ Please note that all Producer workers implement "reliable publishing".
  Each Producer worker handles its publisher confirms _asynchronously_,
  striking a delicate balance between performance and reliability.

  To understand why this is important, please refer to the
  [reliable publishing implementation guide](https://www.rabbitmq.com/tutorials/tutorial-seven-java.html).

  ℹ️ In the unlikely event of an unexpected Publisher `nack`,
  your server will be notified via the `handle_publisher_nack/1` callback,
  letting you handle such exceptions in any way you see fit.

  `handle_publisher_nack/1` is a **required** callback with the following signature, and as such _must_ be implemented
  by your Producer modules, even if it does nothing;

      @type seq_no :: integer()
      @type payload :: String.t()
      @type routing_key :: String.t()
      @type opts :: keyword()
      @type original_publish_args :: {seq_no(), payload(), routing_key(), opts()}
      @type unackd_messages :: list(original_publish_args())
      @type result :: term()

      @callback handle_publisher_nack(unackd_messages()) :: result()

  ## Configuration

  The following options can be used with `RabbitMQ.Producer`;

  * `:confirm_type`;
      publisher acknowledgement mode.
      Only `:async` is supported for now. Please consult the
      [Publisher Confirms](https://www.rabbitmq.com/confirms.html#publisher-confirms)
      section for more details.
      Defaults to `:async`.
  * `:exchange`;
      the name of the exchange onto which the producer workers will publish.
      **Required**.
  * `:worker_count`;
      number of workers to be spawned.
      Cannot be greater than `:max_channels_per_connection` set in config.
      Defaults to `3`.

  When you `use RabbitMQ.Consumer`, a few things happen;

  1. The module turns into a `GenServer`.
  2. The server starts _and supervises_ the desired number of workers.
  3. `publish/3` becomes available in your module.

  `publish/3` is a _private_ function with the following signature;

      @type payload :: String.t()
      @type routing_key :: String.t()
      @type opts :: keyword()
      @type result :: :ok | {:error, :correlation_id_missing}

      publish(payload(), routing_key(), opts()) :: result()

  ⚠️ Please note that `correlation_id` is always required and failing to provide it will result in an exception.

  ℹ️ To see which options can be passed as `opts` to `publish/3`, visit https://hexdocs.pm/amqp/AMQP.Basic.html#publish/5.
  """

  defmacro __using__(opts) do
    quote do
      alias RabbitMQ.Producer

      require Logger

      @confirm_type Keyword.get(unquote(opts), :confirm_type, :async)
      @exchange Keyword.fetch!(unquote(opts), :exchange)
      @worker_count Keyword.get(unquote(opts), :worker_count, 3)
      @this_module __MODULE__

      @behaviour Producer

      ##############
      # Public API #
      ##############

      def child_spec(opts) do
        if @worker_count > max_workers() do
          raise """
          Cannot start #{@worker_count} workers, maximum is #{max_workers()}.

          You can configure this value as shown below;

            config :rabbit_mq, max_channels_per_connection: 16

          As a rule of thumb, most applications can use a single digit number of channels per connection.

          For details, please consult the official RabbitMQ docs: https://www.rabbitmq.com/channels.html#channel-max.
          """
        end

        config = %{
          confirm_type: @confirm_type,
          exchange: @exchange,
          nack_cb: &handle_publisher_nack/1,
          worker_count: @worker_count
        }

        opts = Keyword.put_new(opts, :name, @this_module)

        # Read more about child specification:
        # https://hexdocs.pm/elixir/Supervisor.html#module-child-specification
        %{
          id: @this_module,
          start: {Producer, :start_link, [config, opts]},
          type: :supervisor,
          # Read more about restart values:
          # https://hexdocs.pm/elixir/Supervisor.html#module-restart-values-restart
          restart: :permanent,
          # Read more about shutdown values:
          # https://hexdocs.pm/elixir/Supervisor.html#module-shutdown-values-shutdown
          shutdown: :brutal_kill
        }
      end

      #####################
      # Private Functions #
      #####################

      defp publish(payload, routing_key, opts)
           when is_binary(payload) and is_binary(routing_key) and is_list(opts) do
        with {:ok, producer_pid} <- GenServer.call(@this_module, :get_producer_pid) do
          GenServer.call(producer_pid, {:publish, @exchange, routing_key, payload, opts})
        end
      end

      defp max_workers, do: Application.get_env(:rabbit_mq, :max_channels_per_connection, 8)
    end
  end

  alias AMQP.{Channel, Connection}
  alias RabbitMQ.Producer.Worker

  require Logger

  use GenServer

  @this_module __MODULE__

  @type seq_no :: integer()
  @type payload :: String.t()
  @type routing_key :: String.t()
  @type opts :: keyword()
  @type original_publish_args :: {seq_no(), payload(), routing_key(), opts()}
  @type unackd_messages :: list(original_publish_args())
  @type result :: term()

  @callback handle_publisher_nack(unackd_messages()) :: result()

  defmodule State do
    @moduledoc """
    The internal state held in the `RabbitMQ.Producer` server.

    * `:connection`;
        holds the dedicated `AMQP.Connection`.
    * `:workers`;
        the children started under the server. The server acts as a `Supervisor`.
        Enables round-robin command dispatch.
    * `:worker_count`;
        a simple worker count tracker.
        Used in round-robin command dispatch logic.
    * `:worker_offset`;
        a simple tracker to determine which worker to call next.
        Used in round-robin command dispatch logic.
    """

    @enforce_keys [:connection, :workers, :worker_count]
    defstruct connection: nil, workers: [], worker_count: 0, worker_offset: 0
  end

  ##############
  # Public API #
  ##############

  @doc """
  Starts this module as a process via `GenServer.start_link/3`.

  Only used by the module's `child_spec`.
  """
  @spec start_link(map(), keyword()) :: GenServer.on_start()
  def start_link(config, opts) do
    GenServer.start_link(@this_module, config, opts)
  end

  ######################
  # Callback Functions #
  ######################

  @impl true
  def init(config) do
    Process.flag(:trap_exit, true)

    # Each worker pool will maintain and monitor its own connection.
    {:ok, connection} = connect()

    workers =
      1..config.worker_count
      |> Enum.with_index()
      |> Enum.map(fn {_, index} -> start_worker(index, config, connection) end)

    {:ok, %State{connection: connection, workers: workers, worker_count: config.worker_count}}
  end

  @impl true
  def handle_call(
        :get_producer_pid,
        _from,
        %State{worker_offset: worker_offset, workers: workers, worker_count: worker_count} = state
      ) do
    index = rem(worker_offset, worker_count)
    {_index, pid, _init_arg} = Enum.at(workers, index)

    {:reply, {:ok, pid}, %{state | worker_offset: worker_offset + 1}}
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
    Logger.warn("Producer worker process terminated due to #{inspect(reason)}. Restarting.")

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

  defp start_worker(index, config, connection) do
    {:ok, channel} = Channel.open(connection)

    config =
      config
      |> Map.put(:channel, channel)
      |> Map.take(~w(channel confirm_type nack_cb)a)

    {:ok, pid} = Worker.start_link(config)

    {index, pid, config}
  end

  defp amqp_url, do: Application.fetch_env!(:rabbit_mq, :amqp_url)
  defp heartbeat_interval_sec, do: Application.get_env(:rabbit_mq, :heartbeat_interval_sec, 30)
  defp reconnect_interval_ms, do: Application.get_env(:rabbit_mq, :reconnect_interval_ms, 2500)
  defp max_channels, do: Application.get_env(:rabbit_mq, :max_channels_per_connection, 8)
end
