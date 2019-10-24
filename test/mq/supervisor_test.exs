defmodule MQTest.Supervisor do
  alias MQ.ConnectionManager
  alias MQ.Supervisor, as: RabbitMqSupervisor
  alias MQTest.Support.Consumers.AuditLogMessageProcessor
  alias MQTest.Support.Producers.{AuditLogProducer, ServiceRequestProducer}

  use ExUnit.Case

  @this_module __MODULE__

  # doctest MQ.Supervisor

  describe "MQ.Supervisor" do
    test "starts the connection manager by default" do
      {:ok, _pid} = start_supervised(RabbitMqSupervisor)
      assert {:ok, _channel} = ConnectionManager.request_channel(@this_module)
    end

    test "starts corresponding producer pools when producers are provided in opts" do
      opts = [
        producers: [
          {AuditLogProducer, workers: 2},
          ServiceRequestProducer
        ]
      ]

      {:ok, _pid} = start_supervised({RabbitMqSupervisor, opts})

      assert Process.whereis(AuditLogProducer) |> Process.alive?() == true
      assert Process.whereis(ServiceRequestProducer) |> Process.alive?() == true
    end

    test "starts corresponding consumer pools when consumers are provided in opts" do
      opts = [
        consumers: [
          # Defaults `workers` to `3`.
          {AuditLogMessageProcessor, queue: "audit_log_queue/user_action.*/rabbit_mq_ex"}
        ]
      ]

      {:ok, _pid} = start_supervised({RabbitMqSupervisor, opts})

      assert Process.whereis(AuditLogMessageProcessor) |> Process.alive?() == true
    end
  end
end
