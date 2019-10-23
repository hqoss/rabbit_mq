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

    assert {:ok, queue} = ExclusiveQueue.declare(exchange: "test", routing_key: "test.consumer")

    assert {:ok, _pid} = start_supervised(TestConsumer.child_spec(queue: queue))

    :ok
  end

  setup do
    assert {:ok, reply_to} = TestConsumer.register_reply_to(self())
    publish_opts = [routing_key: "test.consumer", reply_to: reply_to]
    [publish_opts: publish_opts]
  end

  describe "MQ.Consumer" do
    test "consumes messages", %{publish_opts: opts} do
      opts = opts |> Keyword.merge(headers: [{"authorization", "Bearer abc.123"}])

      TestProducer.publish_event("yo", opts)

      assert_receive({:binary, "yo", %{headers: headers}}, 250)
      assert headers == [{"authorization", :longstr, "Bearer abc.123"}]
    end
  end
end
