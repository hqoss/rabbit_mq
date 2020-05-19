defmodule RabbitMQTest.Producer do
  alias RabbitMQ.Producer

  use AMQP
  use ExUnit.Case

  import ExUnit.CaptureLog
  require Logger

  defmodule ProducerWithCallbacks do
    @exchange "#{__MODULE__}"
    @max_overflow :rand.uniform(5)
    @publish_timeout :rand.uniform(500)
    @worker_count :rand.uniform(8)

    use Producer, exchange: @exchange

    def exchange, do: @exchange
    def max_overflow, do: @max_overflow
    def publish_timeout, do: @publish_timeout
    def worker_count, do: @worker_count

    def handle_publisher_ack_confirms(events) do
      Enum.map(events, fn {seq_number, _routing_key, _data, _opts} ->
        Logger.debug("ACK'd #{seq_number}")
      end)
    end

    def handle_publisher_nack_confirms(events) do
      Enum.map(events, fn {seq_number, _routing_key, _data, _opts} ->
        Logger.error("NACK'd #{seq_number}")
      end)
    end
  end

  @amqp_url Application.get_env(:rabbit_mq, :amqp_url)

  @data :crypto.strong_rand_bytes(2_000) |> Base.encode64()
  @exchange "#{__MODULE__}"
  @routing_key :crypto.strong_rand_bytes(16) |> Base.encode16()

  @connection __MODULE__.Connection
  @max_overflow :rand.uniform(5)
  @name __MODULE__
  @publish_timeout :rand.uniform(500)
  @worker_count :rand.uniform(8)
  @worker_pool __MODULE__.WorkerPool

  @base_opts [
    connection: @connection,
    exchange: @exchange,
    max_overflow: @max_overflow,
    name: @name,
    worker_count: @worker_count,
    worker_pool: @worker_pool
  ]

  setup_all do
    assert {:ok, connection} = Connection.open(@amqp_url)
    assert {:ok, channel} = Channel.open(connection)

    # Ensure we have a disposable exchange set up.
    assert :ok = Exchange.declare(channel, @exchange, :direct, durable: false)

    # Clean up after all tests have ran.
    on_exit(fn ->
      assert :ok = Exchange.delete(channel, @exchange)
      assert :ok = Channel.close(channel)
      assert :ok = Connection.close(connection)
    end)

    [channel: channel, opts: @base_opts]
  end

  setup do
    [correlation_id: UUID.uuid4()]
  end

  test "start_link/1 starts a named Supervisor with a dedicated connection, and a worker pool", %{
    opts: opts
  } do
    assert {:ok, pid} = start_supervised({Producer, opts})

    assert {:state, {:local, @name}, :rest_for_one,
            {[:worker_pool, :connection],
             %{
               connection:
                 {:child, _connection_pid, :connection,
                  {RabbitMQ.Connection, :start_link,
                   [[max_channels: @worker_count, name: @connection]]}, :permanent, 5000, :worker,
                  [RabbitMQ.Connection]},
               worker_pool:
                 {:child, _worker_pool_pid, :worker_pool,
                  {:poolboy, :start_link,
                   [
                     [
                       name: {:local, @worker_pool},
                       worker_module: RabbitMQ.Producer.Worker,
                       size: @worker_count,
                       max_overflow: @max_overflow
                     ],
                     [
                       connection: @connection,
                       exchange: @exchange,
                       handle_publisher_ack_confirms: handle_publisher_ack_confirms,
                       handle_publisher_nack_confirms: handle_publisher_nack_confirms
                     ]
                   ]}, :permanent, :infinity, :supervisor, [:poolboy]}
             }}, :undefined, 3, 5, [], 0, RabbitMQ.Producer, @base_opts} = :sys.get_state(pid)

    assert :ok = handle_publisher_ack_confirms.([{0, "routing_key", "data", []}])
    assert :ok = handle_publisher_nack_confirms.([{0, "routing_key", "data", []}])
  end

  test "publishing is facilitated via poolboy", %{
    channel: channel,
    correlation_id: correlation_id,
    opts: opts
  } do
    # Declare an exclusive queue.
    {:ok, %{queue: queue}} = Queue.declare(channel, "", exclusive: true)
    :ok = Queue.bind(channel, queue, @exchange, routing_key: @routing_key)

    assert {:ok, _pid} = start_supervised({Producer, opts})

    # Start receiving Consumer events.
    assert {:ok, consumer_tag} = Basic.consume(channel, queue)

    # This will always be the first message received by the process.
    assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

    publish_opts = [correlation_id: correlation_id]

    assert {:ok, seq_no} =
             Producer.publish({@routing_key, @data, publish_opts}, @worker_pool, @publish_timeout)

    assert_receive(
      {:basic_deliver, @data,
       %{
         correlation_id: ^correlation_id,
         routing_key: @routing_key
       }}
    )

    # Unsubscribe.
    Basic.cancel(channel, consumer_tag)

    # This will always be the last message received by the process.
    assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

    # Ensure no further messages are received.
    refute_receive(_)

    # This queue would have been deleted automatically when the connection
    # gets closed, however we manually delete it to avoid any naming conflicts
    # in between tests, no matter how unlikely. Also, we ensure there are no
    # messages left hanging in the queue.
    assert {:ok, %{message_count: 0}} = Queue.delete(channel, queue)
  end

  test "optional publisher confirm callbacks are passed down to the workers", %{
    opts: opts
  } do
    assert {:ok, _pid} = start_supervised({ProducerWithCallbacks, opts})

    assert {:state, _pid, workers, {[], []}, _ref, 3, 0, 0, :lifo} =
             :sys.get_state(ProducerWithCallbacks.WorkerPool)

    # Pick a random worker
    worker = Enum.random(workers)

    assert %{
             handle_publisher_ack_confirms: handle_publisher_ack_confirms,
             handle_publisher_nack_confirms: handle_publisher_nack_confirms
           } = :sys.get_state(worker)

    assert capture_log(fn ->
             handle_publisher_ack_confirms.([{0, "routing_key", "data", []}])
           end) =~ "ACK'd 0"

    assert capture_log(fn ->
             handle_publisher_nack_confirms.([{1, "routing_key", "data", []}])
           end) =~ "NACK'd 1"
  end

  test "max_workers/0 retrieves the :max_channels_per_connection config" do
    assert Application.get_env(:rabbit_mq, :max_channels_per_connection, 8) ===
             Producer.max_workers()
  end

  test "when used, child_spec/1 returns correctly configured child specification" do
    exchange = ProducerWithCallbacks.exchange()
    max_overflow = ProducerWithCallbacks.max_overflow()
    worker_count = ProducerWithCallbacks.worker_count()

    assert %{
             id: ProducerWithCallbacks,
             start:
               {RabbitMQ.Producer, :start_link,
                [
                  [
                    connection: ProducerWithCallbacks.Connection,
                    exchange: ^exchange,
                    max_overflow: ^max_overflow,
                    name: ProducerWithCallbacks,
                    worker_count: ^worker_count,
                    worker_pool: ProducerWithCallbacks.WorkerPool
                  ]
                ]},
             type: :supervisor
           } = ProducerWithCallbacks.child_spec([])
  end
end
