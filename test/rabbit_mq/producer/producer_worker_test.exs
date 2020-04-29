defmodule RabbitMQTest.Producer.Worker do
  alias AMQP.{Basic, Channel, Connection, Exchange, Queue}
  alias RabbitMQ.Producer.Worker

  require Logger

  use ExUnit.Case

  @amqp_url Application.get_env(:rabbit_mq_ex, :amqp_url)
  @exchange "#{__MODULE__}"

  setup_all do
    assert {:ok, connection} = Connection.open(@amqp_url)
    assert {:ok, channel} = Channel.open(connection)

    # Ensure we have a disposable exchange set up.
    assert :ok = Exchange.declare(channel, @exchange, :topic, durable: false)

    on_exit(fn ->
      # Clean up after all tests have ran.
      assert :ok = Exchange.delete(channel, @exchange)
      assert :ok = Channel.close(channel)
      assert :ok = Connection.close(connection)
    end)

    [channel: channel]
  end

  setup %{channel: channel} do
    # Starts the Producer Worker.
    assert {:ok, pid} =
             start_supervised(
               {Worker,
                %{
                  channel: channel,
                  confirm_type: :async
                }}
             )

    # Declare an exclusive queue and bind it to the "test" exchange.
    {:ok, %{queue: queue}} = Queue.declare(channel, "", exclusive: true)
    :ok = Queue.bind(channel, queue, @exchange, routing_key: "#")

    assert {:ok, consumer_tag} = Basic.consume(channel, queue)

    # This will always be the first message received by the process.
    assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

    on_exit(fn ->
      # This queue would have been deleted automatically when the connection
      # gets closed, however we manually delete it to avoid any naming conflicts
      # in between tests, no matter how unlikely. Also, we ensure there are no
      # messages left hanging in the queue.
      assert {:ok, %{message_count: 0}} = Queue.delete(channel, queue)
    end)

    [
      channel: channel,
      consumer_tag: consumer_tag,
      correlation_id: UUID.uuid4(),
      producer_pid: pid
    ]
  end

  describe "Producer Worker" do
    test "is capable of publishing correctly configured payloads", %{
      channel: channel,
      consumer_tag: consumer_tag,
      correlation_id: correlation_id,
      producer_pid: pid
    } do
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

      Basic.cancel(channel, consumer_tag)

      # This will always be the last message received by the process.
      assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test "fails to publish if correlation_id is not provided in opts", %{
      channel: channel,
      consumer_tag: consumer_tag,
      producer_pid: pid
    } do
      assert {:error, :correlation_id_missing} =
               GenServer.call(pid, {:publish, @exchange, "routing_key", "data", []})

      Basic.cancel(channel, consumer_tag)

      # This will always be the last message received by the process.
      assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

      # Ensure no further messages are received.
      refute_receive(_)
    end
  end
end
