defmodule RabbitMQTest.Producer do
  alias RabbitMQ.Producer

  use AMQP
  use ExUnit.Case

  @amqp_url Application.get_env(:rabbit_mq, :amqp_url)

  @exchange "#{__MODULE__}"

  @connection __MODULE__.Connection
  @counter __MODULE__.Counter
  @producer __MODULE__
  @worker __MODULE__.Worker
  @worker_count 3
  @worker_pool __MODULE__.WorkerPool

  @producer_opts [
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

    [channel: channel, queue: queue]
  end

  setup %{channel: channel, queue: queue} do
    on_exit(fn ->
      # Ensure there are no messages in the queue as the next test is about to start.
      assert true = Queue.empty?(channel, queue)
    end)

    [correlation_id: UUID.uuid4()]
  end

  test "start_link/1 starts a Supervisor with dedicated counter, connection, and worker pool" do
    assert {:ok, _pid} = start_supervised({Producer, @producer_opts})

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
    queue: queue
  } do
    assert {:ok, _pid} = start_supervised({Producer, @producer_opts})

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
    queue: queue
  } do
    assert {:ok, _pid} = start_supervised({Producer, @producer_opts})

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
end
