defmodule Examples.Application do
  alias Examples.Processors.{AuditLogProcessor, LogProcessor}
  alias Examples.Producers.{AuditLogProducer, LogProducer}
  alias MQ.Supervisor

  use Application

  def start(_type, _args) do
    opts = [
      consumers: [
        {AuditLogProcessor, workers: 1, queue: "audit_log_queue/#/example"},
        {LogProcessor, workers: 1, queue: "log_queue/#/example"}
      ],
      producers: [
        {AuditLogProducer, workers: 1},
        {LogProducer, workers: 1}
      ]
    ]

    Supervisor.start_link(opts)
  end
end
