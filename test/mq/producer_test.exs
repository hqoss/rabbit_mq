defmodule MQTest.Producer do
  alias Core.DateTime
  alias MQ.ConnectionManager
  alias MQTest.Support.{RabbitCase, ExclusiveQueue, TestConsumer, Producers}
  alias Producers.{AuditLogProducer, ServiceRequestProducer}

  use RabbitCase

  # @this_module __MODULE__

  # doctest MQ.Consumer

  setup_all do
    assert {:ok, _pid} = start_supervised(AuditLogProducer.child_spec())
    assert {:ok, _pid} = start_supervised(ServiceRequestProducer.child_spec())

    assert {:ok, audit_log_queue} =
             ExclusiveQueue.declare(exchange: "audit_log", routing_key: "user_action.*")

    assert {:ok, service_request_queue} =
             ExclusiveQueue.declare(exchange: "service_request", routing_key: "#")

    assert {:ok, _pid} = start_supervised(TestConsumer.child_spec(queue: audit_log_queue))
    assert {:ok, _pid} = start_supervised(TestConsumer.child_spec(queue: service_request_queue))

    :ok
  end

  setup do
    # Each test process will register its pid (`self()`) so that we can receive
    # corresponding payloads and metadata published via the `Producer`(s).
    assert {:ok, reply_to} = TestConsumer.register_reply_to(self())

    # Each registration generates a unique identifier which will be used
    # in the `TestConsumer`'s message processor module to match against
    # the test process pid previously saved in the registry.s
    publish_opts = [reply_to: reply_to]

    [publish_opts: publish_opts]
  end

  describe "MQ.Producer" do
    test "produces messages with default metadata", %{publish_opts: publish_opts} do
      user_id = UUID.uuid4()
      checkout_reference = UUID.uuid4()
      booking_data = %{user_id: user_id, checkout_reference: checkout_reference}

      # These are sample producers created for testing purposes only..
      assert :ok = AuditLogProducer.publish_event(user_id, :login, publish_opts)
      assert :ok = ServiceRequestProducer.place_booking(booking_data, publish_opts)

      assert_receive(
        {:json, %{"user_id" => ^user_id}, audit_log_meta},
        250
      )

      assert_receive(
        {:json, %{"user_id" => ^user_id, "checkout_reference" => ^checkout_reference},
         service_request_meta},
        250
      )

      assert {:ok, _details} = UUID.info(audit_log_meta.correlation_id)
      assert {:ok, _details} = UUID.info(service_request_meta.correlation_id)

      refute audit_log_meta.timestamp == :undefined
      refute service_request_meta.timestamp == :undefined

      assert audit_log_meta.correlation_id !== service_request_meta.correlation_id
      assert audit_log_meta.timestamp !== service_request_meta.timestamp

      refute_receive 100
    end

    test "produces messages with corresponding metadata", %{publish_opts: opts} do
      user_id = UUID.uuid4()
      correlation_id = UUID.uuid4()
      timestamp = DateTime.now_unix()

      opts =
        opts
        |> Keyword.merge(
          app_id: "rabbit_mq_ex",
          correlation_id: correlation_id,
          headers: [{"authorization", "Bearer abc.123"}],
          timestamp: timestamp
        )

      AuditLogProducer.publish_event(user_id, :logout, opts)

      assert_receive({:json, %{"user_id" => ^user_id}, meta}, 250)

      assert meta.app_id == "rabbit_mq_ex"
      assert meta.correlation_id == correlation_id
      assert meta.headers == [{"authorization", :longstr, "Bearer abc.123"}]
      assert meta.timestamp == timestamp
    end
  end
end
