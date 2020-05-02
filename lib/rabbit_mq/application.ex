defmodule RabbitMQ.Application do
  use Application

  def start(_type, _args) do
    children = []

    # opts = [strategy: :one_for_one, name: RabbitMQ.Supervisor]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
