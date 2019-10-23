defmodule MQTest.Producer do
  alias Core.DateTime
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

    assert {:ok, queue} = ExclusiveQueue.declare(exchange: "test", routing_key: "test.producer")

    assert {:ok, _pid} = start_supervised(TestConsumer.child_spec(queue: queue))

    :ok
  end

  setup do
    assert {:ok, reply_to} = TestConsumer.register_reply_to(self())
    publish_opts = [routing_key: "test.producer", reply_to: reply_to]
    [publish_opts: publish_opts]
  end

  describe "MQ.Producer" do
    test "produces messages with default metadata", %{publish_opts: opts} do
      TestProducer.publish_event("yo", opts)

      assert_receive(
        {:binary, "yo", %{correlation_id: correlation_id, timestamp: timestamp}},
        250
      )

      assert {:ok, _details} = UUID.info(correlation_id)
      refute timestamp == :undefined
    end

    test "produces messages with corresponding metadata", %{publish_opts: opts} do
      correlation_id = UUID.uuid4()
      timestamp = DateTime.now_unix()

      opts =
        opts
        |> Keyword.merge(
          app_id: "test-app",
          correlation_id: correlation_id,
          headers: [{"authorization", "Bearer abc.123"}],
          timestamp: timestamp
        )

      TestProducer.publish_event(Jason.encode!(%{message: "yo"}), opts)

      assert_receive({:json, %{"message" => "yo"}, meta}, 250)

      assert meta.app_id == "test-app"
      assert meta.correlation_id == correlation_id
      assert meta.headers == [{"authorization", :longstr, "Bearer abc.123"}]
      assert meta.timestamp == timestamp
    end
  end
end
