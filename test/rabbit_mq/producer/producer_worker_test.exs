defmodule RabbitMQTest.Producer.Worker do
  alias RabbitMQ.Producer.Worker

  use AMQP
  use ExUnit.Case

  @amqp_url Application.get_env(:rabbit_mq, :amqp_url)

  @data :crypto.strong_rand_bytes(2_000) |> Base.encode64()
  @exchange "#{__MODULE__}"
  @routing_key :crypto.strong_rand_bytes(16) |> Base.encode16()

  @connection __MODULE__.Connection

  @base_opts [
    connection: @connection,
    exchange: @exchange
  ]

  setup_all do
    assert {:ok, _pid} = start_supervised({RabbitMQ.Connection, [name: @connection]})

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

    [channel: channel]
  end

  setup do
    test_pid = self()

    # Declare opts with default publisher confirm callbacks.
    opts =
      @base_opts
      |> Keyword.put(:handle_publisher_ack_confirms, fn events ->
        send(test_pid, {:ack, events})
      end)
      |> Keyword.put(:handle_publisher_nack_confirms, fn events ->
        send(test_pid, {:nack, events})
      end)

    [correlation_id: UUID.uuid4(), opts: opts]
  end

  test "start_link/1 starts a worker and establishes a dedicated channel", %{
    opts: opts
  } do
    assert {:ok, pid} = start_supervised({Worker, opts})

    assert %Worker.State{
             channel: %Channel{} = channel,
             exchange: @exchange,
             outstanding_confirms: []
           } = :sys.get_state(pid)

    assert channel.conn === GenServer.call(@connection, :get)
  end

  test "publishes a message", %{
    channel: channel,
    correlation_id: correlation_id,
    opts: opts
  } do
    # Declare an exclusive queue.
    {:ok, %{queue: queue}} = Queue.declare(channel, "", exclusive: true)
    :ok = Queue.bind(channel, queue, @exchange, routing_key: @routing_key)

    assert {:ok, pid} = start_supervised({Worker, opts})

    # Start receiving Consumer events.
    assert {:ok, consumer_tag} = Basic.consume(channel, queue)

    # This will always be the first message received by the process.
    assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

    publish_opts = [correlation_id: correlation_id]

    assert {:ok, seq_no} = GenServer.call(pid, {:publish, @routing_key, @data, publish_opts})

    assert_receive(
      {:basic_deliver, @data,
       %{
         consumer_tag: ^consumer_tag,
         correlation_id: ^correlation_id,
         delivery_tag: ^seq_no,
         routing_key: @routing_key
       }}
    )

    assert_receive({:ack, [{^seq_no, @routing_key, @data, ^publish_opts}]})

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

  test "[only item] publisher confirm event confirms a single outstanding confirm", %{
    opts: opts
  } do
    assert {:ok, pid} = start_supervised({Worker, opts})

    state =
      pid
      |> :sys.get_state()
      |> Map.put(:outstanding_confirms, [{42, nil, nil, nil}])

    mode = Enum.random([:basic_ack, :basic_nack])
    assert {:noreply, state} = Worker.handle_info({mode, 42, false}, state)

    assert [] = state.outstanding_confirms
  end

  test "[first item] publisher confirm event confirms a single outstanding confirm", %{
    opts: opts
  } do
    assert {:ok, pid} = start_supervised({Worker, opts})

    state =
      pid
      |> :sys.get_state()
      |> Map.put(:outstanding_confirms, [
        {42, nil, nil, nil},
        {41, nil, nil, nil}
      ])

    mode = Enum.random([:basic_ack, :basic_nack])
    assert {:noreply, state} = Worker.handle_info({mode, 42, false}, state)

    assert [{41, nil, nil, nil}] = state.outstanding_confirms
  end

  test "[somewhere in the list] publisher confirm event confirms a single outstanding confirm", %{
    opts: opts
  } do
    assert {:ok, pid} = start_supervised({Worker, opts})

    state =
      pid
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

  test "[first or only item] publisher confirm event confirms multiple outstanding confirms", %{
    opts: opts
  } do
    assert {:ok, pid} = start_supervised({Worker, opts})

    state =
      pid
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

  test "[somewhere in the list] publisher confirm event confirms multiple outstanding confirms",
       %{opts: opts} do
    assert {:ok, pid} = start_supervised({Worker, opts})

    state =
      pid
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

  test "publisher acknowledgement triggers corresponding callback", %{opts: opts} do
    test_pid = self()

    assert {:ok, pid} =
             start_supervised(
               {Worker,
                Keyword.put(opts, :handle_publisher_ack_confirms, fn confirms ->
                  send(test_pid, confirms)
                end)}
             )

    state =
      pid
      |> :sys.get_state()
      |> Map.put(:outstanding_confirms, [{42, nil, nil, nil}])

    multiple? = Enum.random([true, false])
    assert {:noreply, state} = Worker.handle_info({:basic_ack, 42, multiple?}, state)

    assert_receive([{42, nil, nil, nil}])
  end

  test "publisher negative acknowledgement triggers corresponding callback", %{
    opts: opts
  } do
    test_pid = self()

    assert {:ok, pid} =
             start_supervised(
               {Worker,
                Keyword.put(opts, :handle_publisher_nack_confirms, fn confirms ->
                  send(test_pid, confirms)
                end)}
             )

    state =
      pid
      |> :sys.get_state()
      |> Map.put(:outstanding_confirms, [{42, nil, nil, nil}])

    multiple? = Enum.random([true, false])
    assert {:noreply, state} = Worker.handle_info({:basic_nack, 42, multiple?}, state)

    assert_receive([{42, nil, nil, nil}])
  end

  test "when a monitored process dies, an instruction to stop the GenServer is returned", %{
    opts: opts
  } do
    assert {:ok, pid} = start_supervised({Worker, opts})

    state = :sys.get_state(pid)

    assert {:stop, {:channel_down, :failure}, state} =
             Worker.handle_info({:DOWN, :reference, :process, self(), :failure}, state)
  end
end
