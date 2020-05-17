defmodule RabbitMQTest.Producer do
  alias RabbitMQ.Producer

  use AMQP
  use ExUnit.Case

  import ExUnit.CaptureLog
  require Logger

  defmodule ProducerWithCallbacks do
    @exchange "#{__MODULE__}"

    use Producer, exchange: @exchange

    def exchange, do: @exchange

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

  @exchange "#{__MODULE__}"

  @connection __MODULE__.Connection
  @counter __MODULE__.Counter
  @producer __MODULE__
  @worker __MODULE__.Worker
  @worker_count 3
  @worker_pool __MODULE__.WorkerPool

  @base_producer_opts [
    connection: @connection,
    counter: @counter,
    exchange: @exchange,
    name: @producer,
    worker: @worker,
    worker_count: @worker_count,
    worker_pool: @worker_pool
  ]

  setup_all do
    assert {:ok, connection} = Connection.open(@amqp_url)
    assert {:ok, channel} = Channel.open(connection)

    # Ensure we have a disposable exchange set up.
    assert :ok = Exchange.declare(channel, @exchange, :topic, durable: false)

    # Declare an exclusive queue and bind it to the above exchange.
    {:ok, %{queue: queue}} = Queue.declare(channel, "", exclusive: true)
    :ok = Queue.bind(channel, queue, @exchange, routing_key: "#")

    # Declare producer_opts with default publisher confirm callbacks.
    producer_opts =
      @base_producer_opts
      |> Keyword.put(:handle_publisher_ack_confirms, fn _ -> :ok end)
      |> Keyword.put(:handle_publisher_nack_confirms, fn _ -> :ok end)

    # Clean up after all tests have ran.
    on_exit(fn ->
      # This queue would have been deleted automatically when the connection
      # gets closed, however we manually delete it to avoid any naming conflicts
      # in between tests, no matter how unlikely. Also, we ensure there are no
      # messages left hanging in the queue.
      assert {:ok, %{message_count: 0}} = Queue.delete(channel, queue)

      assert :ok = Exchange.delete(channel, @exchange)
      assert :ok = Channel.close(channel)
      assert :ok = Connection.close(connection)
    end)

    [channel: channel, producer_opts: producer_opts, queue: queue]
  end

  setup %{channel: channel, queue: queue} do
    on_exit(fn ->
      # Ensure there are no messages in the queue as the next test is about to start.
      assert true = Queue.empty?(channel, queue)
    end)

    [correlation_id: UUID.uuid4()]
  end

  test "start_link/1 starts a Supervisor with dedicated counter, connection, and worker pool", %{
    producer_opts: producer_opts
  } do
    assert {:ok, _pid} = start_supervised({Producer, producer_opts})

    assert [{:offset, -1}] = :ets.lookup(@counter, :offset)

    assert [
             {:worker_pool, _worker_pool_pid, :supervisor, [RabbitMQ.Producer.WorkerPool]},
             {:connection, _connection_pid, :worker, [RabbitMQ.Connection]}
           ] = Supervisor.which_children(@producer)

    # Check whether the worker pool has exactly 3 children.
    assert @worker_count === @worker_pool |> Supervisor.which_children() |> Enum.count()
  end

  test "dispatch/4 updates the counter and publishes to the corresponding module", %{
    channel: channel,
    correlation_id: correlation_id,
    producer_opts: producer_opts,
    queue: queue
  } do
    assert {:ok, _pid} = start_supervised({Producer, producer_opts})

    assert [{:offset, -1}] = :ets.lookup(@counter, :offset)

    # Start receiving Consumer events.
    assert {:ok, consumer_tag} = Basic.consume(channel, queue)

    # This will always be the first message received by the process.
    assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

    opts = [correlation_id: correlation_id]

    assert {:ok, seq_no} =
             Producer.dispatch({"routing_key", "data", opts}, @counter, @worker, @worker_count)

    assert [{:offset, 0}] = :ets.lookup(@counter, :offset)

    assert_receive({:basic_deliver, "data", %{correlation_id: ^correlation_id}})

    # Unsubscribe.
    Basic.cancel(channel, consumer_tag)

    # This will always be the last message received by the process.
    assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

    # Ensure no further messages are received.
    refute_receive(_)
  end

  test "dispatch/4 resets the counter when the threshold is reached", %{
    channel: channel,
    correlation_id: correlation_id,
    producer_opts: producer_opts,
    queue: queue
  } do
    assert {:ok, _pid} = start_supervised({Producer, producer_opts})

    assert true = :ets.insert(@counter, {:offset, 100_000})

    # Start receiving Consumer events.
    assert {:ok, consumer_tag} = Basic.consume(channel, queue)

    # This will always be the first message received by the process.
    assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

    opts = [correlation_id: correlation_id]

    assert {:ok, seq_no} =
             Producer.dispatch({"routing_key", "data", opts}, @counter, @worker, @worker_count)

    assert [{:offset, 0}] = :ets.lookup(@counter, :offset)

    assert_receive({:basic_deliver, "data", %{correlation_id: ^correlation_id}})

    # Unsubscribe.
    Basic.cancel(channel, consumer_tag)

    # This will always be the last message received by the process.
    assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

    # Ensure no further messages are received.
    refute_receive(_)
  end

  test "default publisher confirm callbacks are passed down to the workers", %{
    producer_opts: producer_opts
  } do
    assert {:ok, _pid} = start_supervised({Producer, producer_opts})

    # Pick a random child (index)
    child_id = 0..2 |> Enum.random() |> Integer.to_string()
    worker = Module.concat(@worker, child_id)

    assert %{
             handle_publisher_ack_confirms: handle_publisher_ack_confirms,
             handle_publisher_nack_confirms: handle_publisher_nack_confirms
           } = Process.whereis(worker) |> :sys.get_state()

    assert capture_log(fn ->
             handle_publisher_ack_confirms.([{0, "routing_key", "data", []}])
           end) =~ "Publisher acknowledged 0"

    assert capture_log(fn ->
             handle_publisher_nack_confirms.([{1, "routing_key", "data", []}])
           end) =~ "Publisher negatively acknowledged 1"
  end

  test "optional publisher confirm callbacks are passed down to the workers", %{
    producer_opts: producer_opts
  } do
    assert {:ok, _pid} = start_supervised({ProducerWithCallbacks, producer_opts})

    # Pick a random child (index)
    child_id = 0..2 |> Enum.random() |> Integer.to_string()
    worker = Module.concat(ProducerWithCallbacks.Worker, child_id)

    assert %{
             handle_publisher_ack_confirms: handle_publisher_ack_confirms,
             handle_publisher_nack_confirms: handle_publisher_nack_confirms
           } = Process.whereis(worker) |> :sys.get_state()

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

    assert %{
             id: ProducerWithCallbacks,
             start:
               {RabbitMQ.Producer, :start_link,
                [
                  [
                    connection: ProducerWithCallbacks.Connection,
                    counter: ProducerWithCallbacks.Counter,
                    exchange: ^exchange,
                    name: ProducerWithCallbacks,
                    worker: ProducerWithCallbacks.Worker,
                    worker_count: 3,
                    worker_pool: ProducerWithCallbacks.WorkerPool
                  ]
                ]},
             type: :supervisor
           } = ProducerWithCallbacks.child_spec([])
  end
end
