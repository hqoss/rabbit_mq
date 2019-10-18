defmodule MQTest.Consumer do
  alias MQ.ConnectionManager
  alias MQ.Support.{RabbitCase, ExclusiveQueue, TestConsumer}
  alias MQTest.Support.TestProducer

  use RabbitCase

  # @this_module __MODULE__

  # doctest MQ.Consumer

  setup_all do
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
