defmodule RabbitMQTest.Producer.Worker do
  alias AMQP.{Basic, Channel, Connection, Exchange, Queue}
  alias RabbitMQ.Producer.Worker

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

    [
      channel: channel,
      correlation_id: UUID.uuid4()
    ]
  end

  describe "#{__MODULE__}" do
    test "is capable of publishing correctly configured payloads", %{
      channel: channel,
      correlation_id: correlation_id,
      queue: queue
    } do
      assert {:ok, pid} =
               start_supervised(
                 {Worker,
                  %{
                    channel: channel,
                    confirm_type: :async
                  }}
               )

      # This process will now start receiving events.
      assert {:ok, consumer_tag} = Basic.consume(channel, queue)

      # This will always be the first message received by the process.
      assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

      opts = [correlation_id: correlation_id]

      assert {:ok, seq_no} =
               GenServer.call(pid, {:publish, @exchange, "routing_key", "data", opts})

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

    test "fails to publish if correlation_id is not provided in opts", %{
      channel: channel,
      queue: queue
    } do
      assert {:ok, pid} =
               start_supervised(
                 {Worker,
                  %{
                    channel: channel,
                    confirm_type: :async
                  }}
               )

      # This process will now start receiving events.
      assert {:ok, consumer_tag} = Basic.consume(channel, queue)

      # This will always be the first message received by the process.
      assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

      assert {:error, :correlation_id_missing} =
               GenServer.call(pid, {:publish, @exchange, "routing_key", "data", []})

      # Unsubscribe
      Basic.cancel(channel, consumer_tag)

      # This will always be the last message received by the process.
      assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test ":basic_ack deletes outstanding confirm", %{channel: channel} do
      assert {:ok, pid} =
               start_supervised(
                 {Worker,
                  %{
                    channel: channel,
                    confirm_type: :async
                  }}
               )

      assert %Worker.State{
               outstanding_confirms: outstanding_confirms
             } = :sys.get_state(pid)

      assert [] = :ets.tab2list(outstanding_confirms)

      :ets.insert(outstanding_confirms, {0, "payload_0"})
      :ets.insert(outstanding_confirms, {1, "payload_1"})
      :ets.insert(outstanding_confirms, {2, "payload_2"})

      assert [
               {0, "payload_0"},
               {1, "payload_1"},
               {2, "payload_2"}
             ] = :ets.tab2list(outstanding_confirms)

      send(pid, {:basic_ack, 1, false})

      :timer.sleep(5)

      assert [
               {0, "payload_0"},
               {2, "payload_2"}
             ] = :ets.tab2list(outstanding_confirms)
    end

    test ":basic_ack deletes multiple outstanding confirms", %{channel: channel} do
      assert {:ok, pid} =
               start_supervised(
                 {Worker,
                  %{
                    channel: channel,
                    confirm_type: :async
                  }}
               )

      assert %Worker.State{
               outstanding_confirms: outstanding_confirms
             } = :sys.get_state(pid)

      assert [] = :ets.tab2list(outstanding_confirms)

      :ets.insert(outstanding_confirms, {0, "payload_0"})
      :ets.insert(outstanding_confirms, {1, "payload_1"})
      :ets.insert(outstanding_confirms, {2, "payload_2"})

      assert [
               {0, "payload_0"},
               {1, "payload_1"},
               {2, "payload_2"}
             ] = :ets.tab2list(outstanding_confirms)

      send(pid, {:basic_ack, 2, true})

      :timer.sleep(5)

      assert [] = :ets.tab2list(outstanding_confirms)
    end
  end
end
