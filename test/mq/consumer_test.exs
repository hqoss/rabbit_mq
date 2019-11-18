defmodule MQTest.Consumer do
  alias MQ.ConnectionManager
  alias MQ.Support.{RabbitCase, ExclusiveQueue, TestConsumer}
  alias MQTest.Support.Producers.AuditLogProducer

  use RabbitCase

  setup_all do
    assert {:ok, _pid} = start_supervised(AuditLogProducer.child_spec())

    assert {:ok, queue} =
             ExclusiveQueue.declare(exchange: "audit_log", routing_key: "user_action.*")

    assert {:ok, _pid} = start_supervised(TestConsumer.child_spec(queue: queue))

    :ok
  end

  setup do
    assert {:ok, reply_to} = TestConsumer.register_reply_to(self())
    publish_opts = [reply_to: reply_to]
    [publish_opts: publish_opts]
  end

  describe "MQ.Consumer" do
    test "consumes messages", %{publish_opts: publish_opts} do
      user_id = UUID.uuid4()

      AuditLogProducer.publish_event(user_id, :login, publish_opts)

      assert_receive({:json, %{"user_id" => ^user_id}, meta}, 250)

      assert meta.routing_key == "user_action.login"

      refute_receive 100
    end
  end
end
