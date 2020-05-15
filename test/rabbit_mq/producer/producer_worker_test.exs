defmodule RabbitMQTest.Producer.Worker do
  alias RabbitMQ.Producer.Worker

  use AMQP
  use ExUnit.Case

  @exchange "#{__MODULE__}"

  @connection __MODULE__.Connection
  @worker __MODULE__

  @worker_opts [connection: @connection, exchange: @exchange, name: @worker]

  setup_all do
    assert {:ok, _pid} = start_supervised({RabbitMQ.Connection, [name: @connection]})

    connection = GenServer.call(@connection, :get)
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

  test "start_link/1 starts a worker and establishes a dedicated channel" do
    assert {:ok, pid} = start_supervised({Worker, @worker_opts})

    assert %Worker.State{
             channel: %Channel{} = channel,
             exchange: @exchange,
             outstanding_confirms: []
           } = :sys.get_state(pid)

    assert channel.conn === GenServer.call(@connection, :get)
  end

  test "publishes a message", %{channel: channel, correlation_id: correlation_id, queue: queue} do
    assert {:ok, pid} = start_supervised({Worker, @worker_opts})

    # Start receiving Consumer events.
    assert {:ok, consumer_tag} = Basic.consume(channel, queue)

    # This will always be the first message received by the process.
    assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

    opts = [correlation_id: correlation_id]

    assert {:ok, seq_no} = GenServer.call(@worker, {:publish, "routing_key", "data", opts})

    assert_receive(
      {:basic_deliver, "data",
       %{
         consumer_tag: ^consumer_tag,
         correlation_id: ^correlation_id,
         delivery_tag: ^seq_no,
         routing_key: "routing_key"
       }}
    )

    # Unsubscribe.
    Basic.cancel(channel, consumer_tag)

    # This will always be the last message received by the process.
    assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

    # Ensure no further messages are received.
    refute_receive(_)
  end

  test "[only item] publisher confirm event confirms a single outstanding confirm" do
    assert {:ok, pid} = start_supervised({Worker, @worker_opts})

    state =
      @worker
      |> :sys.get_state()
      |> Map.put(:outstanding_confirms, [{42, nil, nil, nil}])

    mode = Enum.random([:basic_ack, :basic_nack])
    assert {:noreply, state} = Worker.handle_info({mode, 42, false}, state)

    assert [] = state.outstanding_confirms
  end

  test "[first item] publisher confirm event confirms a single outstanding confirm" do
    assert {:ok, pid} = start_supervised({Worker, @worker_opts})

    state =
      @worker
      |> :sys.get_state()
      |> Map.put(:outstanding_confirms, [
        {42, nil, nil, nil},
        {41, nil, nil, nil}
      ])

    mode = Enum.random([:basic_ack, :basic_nack])
    assert {:noreply, state} = Worker.handle_info({mode, 42, false}, state)

    assert [{41, nil, nil, nil}] = state.outstanding_confirms
  end

  test "[somewhere in the list] publisher confirm event confirms a single outstanding confirm" do
    assert {:ok, pid} = start_supervised({Worker, @worker_opts})

    state =
      @worker
      |> :sys.get_state()
      |> Map.put(:outstanding_confirms, [
        {43, nil, nil, nil},
        {42, nil, nil, nil},
        {41, nil, nil, nil}
      ])

    mode = Enum.random([:basic_ack, :basic_nack])
    assert {:noreply, state} = Worker.handle_info({mode, 42, false}, state)

    assert [
             {43, nil, nil, nil},
             {41, nil, nil, nil}
           ] = state.outstanding_confirms
  end

  test "[first or only item] publisher confirm event confirms multiple outstanding confirms" do
    assert {:ok, pid} = start_supervised({Worker, @worker_opts})

    state =
      @worker
      |> :sys.get_state()
      |> Map.put(:outstanding_confirms, [
        {42, nil, nil, nil},
        {41, nil, nil, nil},
        {40, nil, nil, nil}
      ])

    mode = Enum.random([:basic_ack, :basic_nack])
    assert {:noreply, state} = Worker.handle_info({mode, 42, true}, state)

    assert [] = state.outstanding_confirms
  end

  test "[somewhere in the list] publisher confirm event confirms multiple outstanding confirms" do
    assert {:ok, pid} = start_supervised({Worker, @worker_opts})

    state =
      @worker
      |> :sys.get_state()
      |> Map.put(:outstanding_confirms, [
        {43, nil, nil, nil},
        {42, nil, nil, nil},
        {41, nil, nil, nil}
      ])

    mode = Enum.random([:basic_ack, :basic_nack])
    assert {:noreply, state} = Worker.handle_info({mode, 42, true}, state)

    assert [{43, nil, nil, nil}] = state.outstanding_confirms
  end

  test "publisher acknowledgement triggers corresponding callback" do
    test_pid = self()

    assert {:ok, pid} =
             start_supervised(
               {Worker,
                Keyword.put(@worker_opts, :handle_publisher_ack, fn confirms ->
                  send(test_pid, confirms)
                end)}
             )

    state =
      @worker
      |> :sys.get_state()
      |> Map.put(:outstanding_confirms, [{42, nil, nil, nil}])

    multiple? = Enum.random([true, false])
    assert {:noreply, state} = Worker.handle_info({:basic_ack, 42, multiple?}, state)

    assert_receive([{42, nil, nil, nil}])
  end

  test "publisher negative acknowledgement triggers corresponding callback" do
    test_pid = self()

    assert {:ok, pid} =
             start_supervised(
               {Worker,
                Keyword.put(@worker_opts, :handle_publisher_nack, fn confirms ->
                  send(test_pid, confirms)
                end)}
             )

    state =
      @worker
      |> :sys.get_state()
      |> Map.put(:outstanding_confirms, [{42, nil, nil, nil}])

    multiple? = Enum.random([true, false])
    assert {:noreply, state} = Worker.handle_info({:basic_nack, 42, multiple?}, state)

    assert_receive([{42, nil, nil, nil}])
  end

  test "when a monitored process dies, an instruction to stop the GenServer is returned" do
    assert {:ok, pid} = start_supervised({Worker, @worker_opts})

    state = :sys.get_state(@worker)

    assert {:stop, {:channel_down, :failure}, state} =
             Worker.handle_info({:DOWN, :reference, :process, self(), :failure}, state)
  end
end
