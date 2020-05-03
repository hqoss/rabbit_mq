defmodule RabbitMQTest.Consumer.Worker do
  alias AMQP.{Basic, Channel, Connection, Exchange, Queue}
  alias RabbitMQ.Consumer.Worker

  require Logger

  use ExUnit.Case

  @amqp_url Application.get_env(:rabbit_mq, :amqp_url)
  @exchange "#{__MODULE__}"

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

    [channel: channel, correlation_id: UUID.uuid4()]
  end

  describe "#{__MODULE__}" do
    test "is capable of consuming messages", %{
      channel: channel,
      correlation_id: correlation_id,
      queue: queue
    } do
      # Capture current process pid to send a message to when `consume_cb` is called.
      test_pid = self()

      # Starts the Consumer Worker.
      assert {:ok, pid} =
               start_supervised(
                 {Worker,
                  %{
                    channel: channel,
                    consume_cb: fn payload, meta, channel ->
                      send(test_pid, {payload, meta})
                      Basic.ack(channel, meta.delivery_tag)
                    end,
                    queue: queue,
                    prefetch_count: 10
                  }}
               )

      opts = [correlation_id: correlation_id]

      assert :ok = Basic.publish(channel, @exchange, "routing_key", "data", opts)

      assert_receive(
        {"data",
         %{
           correlation_id: ^correlation_id,
           exchange: @exchange,
           routing_key: "routing_key"
         }}
      )

      # Ensure no further messages are received.
      refute_receive(_)
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

    test "implements :basic_deliver callback", %{channel: channel, correlation_id: correlation_id} do
      # Capture current process pid to send a message to when `consume_cb` is called.
      test_pid = self()

      state = %Worker.State{
        channel: channel,
        consume_cb: fn payload, meta, channel ->
          send(test_pid, {payload, meta})
          Basic.ack(channel, meta.delivery_tag)
        end,
        consumer_tag: UUID.uuid4()
      }

      assert {:noreply, ^state} =
               Worker.handle_info(
                 {:basic_deliver, "data", %{correlation_id: correlation_id}},
                 state
               )

      assert_receive({"data", %{correlation_id: ^correlation_id}})
    end
  end
end
