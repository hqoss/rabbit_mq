defmodule RabbitMQTest.Topology do
  alias AMQP.{Basic, Channel, Connection, Exchange, Queue}
  alias RabbitMQ.Topology

  use ExUnit.Case

  @amqp_url Application.get_env(:rabbit_mq, :amqp_url)

  defmodule TestTopology do
    use Topology,
      exchanges: [
        {"test_exchange_direct", :direct,
         [{"routing_key", "test_exchange_direct_queue/routing_key", durable: true}]},
        {"test_exchange_topic", :topic, [{"routing.*", "test_exchange_topic_queue/routing.*"}],
         durable: true},
        {"test_exchange_fanout", :fanout,
         [{"", "test_exchange_fanout_queue", arguments: [{"x-max-length", :signedint, 10}]}]}
      ]
  end

  setup_all do
    assert {:ok, connection} = Connection.open(@amqp_url)
    assert {:ok, channel} = Channel.open(connection)

    assert {:ok, pid} = start_supervised(TestTopology)

    # Clean up after all tests have ran.
    on_exit(fn ->
      # Ensure there are no messages left hanging in the queue as it gets deleted.
      assert {:ok, %{message_count: 0}} =
               Queue.delete(channel, "test_exchange_direct_queue/routing_key")

      assert {:ok, %{message_count: 0}} =
               Queue.delete(channel, "test_exchange_topic_queue/routing.*")

      assert {:ok, %{message_count: 0}} = Queue.delete(channel, "test_exchange_fanout_queue")

      assert :ok = Exchange.delete(channel, "test_exchange_direct")
      assert :ok = Exchange.delete(channel, "test_exchange_topic")
      assert :ok = Exchange.delete(channel, "test_exchange_fanout")

      assert :ok = Channel.close(channel)
      assert :ok = Connection.close(connection)
    end)

    [channel: channel]
  end

  setup %{channel: channel} do
    Basic.return(channel, self())
  end

  describe "#{__MODULE__}" do
    test "correctly sets up direct exchange", %{channel: channel} do
      assert :ok = Basic.publish(channel, "test_exchange_direct", "routing_key", "routable_data")

      assert {:ok, "routable_data",
              %{
                delivery_tag: delivery_tag,
                routing_key: "routing_key"
              }} = Basic.get(channel, "test_exchange_direct_queue/routing_key")

      assert :ok = Basic.ack(channel, delivery_tag)

      assert :ok =
               Basic.publish(
                 channel,
                 "test_exchange_direct",
                 "unknown_routing_key",
                 "unroutable_data",
                 mandatory: true
               )

      assert_receive({:basic_return, "unroutable_data", %{routing_key: "unknown_routing_key"}})

      assert :ok = Basic.cancel_return(channel)
    end

    test "correctly sets up topic exchange", %{channel: channel} do
      assert :ok = Basic.publish(channel, "test_exchange_topic", "routing.key", "routable_data")

      assert {:ok, "routable_data",
              %{
                delivery_tag: delivery_tag,
                routing_key: "routing.key"
              }} = Basic.get(channel, "test_exchange_topic_queue/routing.*")

      assert :ok = Basic.ack(channel, delivery_tag)

      assert :ok =
               Basic.publish(
                 channel,
                 "test_exchange_topic",
                 "routing.key.unknown",
                 "unroutable_data",
                 mandatory: true
               )

      assert_receive({:basic_return, "unroutable_data", %{routing_key: "routing.key.unknown"}})

      assert :ok = Basic.cancel_return(channel)
    end

    test "correctly sets up fanout exchange", %{channel: channel} do
      assert :ok = Basic.publish(channel, "test_exchange_fanout", "routing_key", "routable_data")

      assert {:ok, "routable_data",
              %{
                delivery_tag: delivery_tag,
                routing_key: "routing_key"
              }} = Basic.get(channel, "test_exchange_fanout_queue")

      assert :ok = Basic.ack(channel, delivery_tag)

      assert :ok =
               Basic.publish(
                 channel,
                 "test_exchange_fanout",
                 "any_routing_key",
                 "routable_data",
                 mandatory: true
               )

      assert {:ok, "routable_data",
              %{
                delivery_tag: delivery_tag,
                routing_key: "any_routing_key"
              }} = Basic.get(channel, "test_exchange_fanout_queue")

      assert :ok = Basic.ack(channel, delivery_tag)

      refute_receive(_)

      assert :ok = Basic.cancel_return(channel)
    end
  end
end
