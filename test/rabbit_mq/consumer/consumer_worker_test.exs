defmodule RabbitMQTest.Consumer.Worker do
  alias RabbitMQ.Consumer.Worker

  use AMQP
  use ExUnit.Case

  @amqp_url Application.get_env(:rabbit_mq, :amqp_url)

  @data :crypto.strong_rand_bytes(2_000) |> Base.encode64()
  @exchange "#{__MODULE__}"
  @routing_key :crypto.strong_rand_bytes(16) |> Base.encode16()

  @connection __MODULE__.Connection
  @prefetch_count :rand.uniform(10)

  @base_opts [
    connection: @connection,
    exchange: @exchange,
    prefetch_count: @prefetch_count,
    queue: {@exchange, @routing_key}
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

    # Declare opts with a default consume callback.
    opts =
      @base_opts
      |> Keyword.put(:consume_cb, fn data, meta, channel ->
        Basic.ack(channel, meta.delivery_tag)
        send(test_pid, {data, meta})
      end)

    [correlation_id: UUID.uuid4(), opts: opts]
  end

  describe "#{__MODULE__}" do
    test "start_link/1 starts a worker and establishes a dedicated channel", %{
      opts: opts
    } do
      assert {:ok, pid} = start_supervised({Worker, opts})

      consume_cb = opts[:consume_cb]

      assert %Worker.State{
               channel: %Channel{} = channel,
               consume_cb: ^consume_cb,
               consumer_tag: _
             } = :sys.get_state(pid)

      assert channel.conn === GenServer.call(@connection, :get)
    end

    test "starts a consumer, declares and uses an exclusive queue, invokes consume_cb when message is received",
         %{
           channel: channel,
           correlation_id: correlation_id,
           opts: opts
         } do
      assert {:ok, pid} = start_supervised({Worker, opts})

      assert %Worker.State{consumer_tag: consumer_tag} = :sys.get_state(pid)

      assert :ok =
               Basic.publish(channel, @exchange, @routing_key, @data,
                 correlation_id: correlation_id
               )

      assert_receive(
        {@data,
         %{
           correlation_id: ^correlation_id,
           consumer_tag: consumer_tag,
           exchange: @exchange,
           routing_key: @routing_key
         }}
      )

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test "starts a consumer, declares and uses an exclusive queue with opts, invokes consume_cb when message is received",
         %{
           channel: channel,
           correlation_id: correlation_id,
           opts: opts
         } do
      arguments = [{"x-message-ttl", :signedint, 60_000}]
      opts = Keyword.put(opts, :queue, {@exchange, @routing_key, [arguments: arguments]})

      assert {:ok, pid} = start_supervised({Worker, opts})

      assert %Worker.State{consumer_tag: consumer_tag} = :sys.get_state(pid)

      assert :ok =
               Basic.publish(channel, @exchange, @routing_key, @data,
                 correlation_id: correlation_id
               )

      assert_receive(
        {@data,
         %{
           correlation_id: ^correlation_id,
           consumer_tag: consumer_tag,
           exchange: @exchange,
           routing_key: @routing_key
         }}
      )

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test "starts a consumer, declares and uses a named exclusive queue, invokes consume_cb when message is received",
         %{
           channel: channel,
           correlation_id: correlation_id,
           opts: opts
         } do
      queue = :crypto.strong_rand_bytes(16) |> Base.encode16()
      opts = Keyword.put(opts, :queue, {@exchange, @routing_key, queue})

      assert {:ok, pid} = start_supervised({Worker, opts})

      assert %Worker.State{consumer_tag: consumer_tag} = :sys.get_state(pid)

      assert :ok =
               Basic.publish(channel, @exchange, @routing_key, @data,
                 correlation_id: correlation_id
               )

      assert_receive(
        {@data,
         %{
           correlation_id: ^correlation_id,
           consumer_tag: consumer_tag,
           exchange: @exchange,
           routing_key: @routing_key
         }}
      )

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test "starts a consumer, declares and uses a named exclusive queue with opts, invokes consume_cb when message is received",
         %{
           channel: channel,
           correlation_id: correlation_id,
           opts: opts
         } do
      arguments = [{"x-message-ttl", :signedint, 60_000}]
      queue = :crypto.strong_rand_bytes(16) |> Base.encode16()
      opts = Keyword.put(opts, :queue, {@exchange, @routing_key, queue, [arguments: arguments]})

      assert {:ok, pid} = start_supervised({Worker, opts})

      assert %Worker.State{consumer_tag: consumer_tag} = :sys.get_state(pid)

      assert :ok =
               Basic.publish(channel, @exchange, @routing_key, @data,
                 correlation_id: correlation_id
               )

      assert_receive(
        {@data,
         %{
           correlation_id: ^correlation_id,
           consumer_tag: consumer_tag,
           exchange: @exchange,
           routing_key: @routing_key
         }}
      )

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test "starts a consumer, uses a pre-defined queue, invokes consume_cb when message is received",
         %{
           correlation_id: correlation_id,
           opts: opts
         } do
      # Declare an exclusive queue.
      # Must be bound to the connection our consumer will be using.
      connection = GenServer.call(@connection, :get)
      {:ok, channel} = Channel.open(connection)

      {:ok, %{queue: queue}} = Queue.declare(channel, "", exclusive: true)
      :ok = Queue.bind(channel, queue, @exchange, routing_key: @routing_key)

      opts = Keyword.put(opts, :queue, queue)
      assert {:ok, pid} = start_supervised({Worker, opts}, restart: :temporary)

      assert %Worker.State{consumer_tag: consumer_tag} = :sys.get_state(pid)

      assert :ok =
               Basic.publish(channel, @exchange, @routing_key, @data,
                 correlation_id: correlation_id
               )

      assert_receive(
        {@data,
         %{
           correlation_id: ^correlation_id,
           consumer_tag: consumer_tag,
           exchange: @exchange,
           routing_key: @routing_key
         }}
      )

      # Ensure no further messages are received.
      refute_receive(_)

      # This queue would have been deleted automatically when the connection
      # gets closed, however we manually delete it to avoid any naming conflicts
      # in between tests, no matter how unlikely. Also, we ensure there are no
      # messages left hanging in the queue.
      assert {:ok, %{message_count: 0}} = Queue.delete(channel, queue)

      assert :ok = Channel.close(channel)
    end

    test "when a monitored process dies, an instruction to stop the GenServer is returned", %{
      opts: opts
    } do
      assert {:ok, pid} = start_supervised({Worker, opts})

      state = :sys.get_state(pid)

      assert {:stop, {:channel_down, :failure}, state} =
               Worker.handle_info({:DOWN, :reference, :process, self(), :failure}, state)
    end

    test "implements :basic_consume_ok callback", %{channel: channel} do
      state = %Worker.State{
        channel: channel,
        consume_cb: fn _, _, _ -> :ok end,
        consumer_tag: UUID.uuid4()
      }

      assert {:noreply, ^state} =
               Worker.handle_info({:basic_consume_ok, %{consumer_tag: state.consumer_tag}}, state)
    end

    test "implements :basic_cancel_ok callback", %{channel: channel} do
      state = %Worker.State{
        channel: channel,
        consume_cb: fn _, _, _ -> :ok end,
        consumer_tag: UUID.uuid4()
      }

      assert {:noreply, ^state} =
               Worker.handle_info({:basic_cancel_ok, %{consumer_tag: state.consumer_tag}}, state)
    end

    test "implements :basic_cancel callback", %{channel: channel} do
      state = %Worker.State{
        channel: channel,
        consume_cb: fn _, _, _ -> :ok end,
        consumer_tag: UUID.uuid4()
      }

      assert {:noreply, ^state} =
               Worker.handle_info({:basic_cancel, %{consumer_tag: state.consumer_tag}}, state)
    end
  end
end
