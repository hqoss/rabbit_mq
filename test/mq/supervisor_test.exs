defmodule MQTest.Supervisor do
  alias Examples.Processors.{AuditLogProcessor, LogProcessor}
  alias Examples.Producers.{AuditLogProducer, LogProducer}
  alias MQ.ConnectionManager
  alias MQ.Supervisor, as: RabbitMq

  use ExUnit.Case

  @this_module __MODULE__

  # doctest MQ

  describe "MQ.Supervisor" do
    test "starts the connection manager by default" do
      {:ok, _pid} = start_supervised(RabbitMq)
      assert {:ok, _channel} = ConnectionManager.request_channel(@this_module)
    end

    test "starts corresponding producer pools when producers are provided in opts" do
      opts = [
        producers: [
          {AuditLogProducer, workers: 1},
          {LogProducer, workers: 1}
        ]
      ]

      {:ok, _pid} = start_supervised({RabbitMq, opts})

      assert Process.whereis(AuditLogProducer) |> Process.alive?() == true
      assert Process.whereis(LogProducer) |> Process.alive?() == true
    end

    test "starts corresponding consumer pools when consumers are provided in opts" do
      opts = [
        consumers: [
          {AuditLogProcessor, workers: 1, queue: "audit_log_queue/#/example"},
          {LogProcessor, workers: 1, queue: "log_queue/#/example"}
        ]
      ]

      {:ok, _pid} = start_supervised({RabbitMq, opts})

      assert Process.whereis(AuditLogProcessor) |> Process.alive?() == true
      assert Process.whereis(LogProcessor) |> Process.alive?() == true
    end
  end
end
