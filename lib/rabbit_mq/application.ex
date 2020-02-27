defmodule RabbitMQ.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TransactionProducer,
      TransactionConsumer
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: RabbitMQ.Supervisor)
  end
end
