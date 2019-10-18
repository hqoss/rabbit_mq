defmodule MQTest.Consumer do
  alias Examples.Config.Exchanges
  alias MQ.Topology.{Config, Queue}
  alias MQ.ConnectionManager
  alias MQ.Support.{ExclusiveQueue, TestConsumer}
  alias MQTest.Support.TestProducer

  use ExUnit.Case

  # @this_module __MODULE__

  # doctest MQ.Consumer

  setup_all do
    exchanges = Exchanges.gen()
    topology = Config.gen(exchanges)
    Queue.purge_all(topology)

    assert {:ok, _pid} = start_supervised(ConnectionManager)

    assert {:ok, _pid} =
             start_supervised(
               TestProducer.child_spec(module: TestProducer, workers: 1, worker_overflow: 0)
             )

    assert {:ok, queue} =
             ExclusiveQueue.declare(exchange: "test", routing_key: "test.routing_key")

    [queue: queue]
  end

  setup %{queue: queue} do
    assert {:ok, _pid} = start_supervised(TestConsumer.child_spec(queue: queue, pid: self()))
    :ok
  end

  describe "MQ.Consumer" do
    test "consumes messages" do
      headers = [{"authorization", "Bearer abc.123"}]
      opts = [headers: headers, routing_key: "test.routing_key"]

      TestProducer.publish_event("yo", opts)

      assert_receive({:binary, "yo", %{headers: headers}}, 250)
      assert headers == [{"authorization", :longstr, "Bearer abc.123"}]
    end
  end
end
