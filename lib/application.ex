defmodule MQ.Application do
  @moduledoc """
  See https://hexdocs.pm/elixir/Application.html
  for more information on OTP Applications.
  """

  # alias MQ.ChildSpecs
  alias MQ.ConnectionManager

  use Application

  @name :mq_supervisor

  def start(_type, _args) do
    # consumers = Application.get_env(:rabbitex, :consumers, [])

    # consumers =
    #   [
    #     {Sample.Processor, [workers: 3, queue: "test_queue"]},
    #     {Sample.Processor.Another, [workers: 6, queue: "test_queue"]}
    #   ]
    #   |> Topology.consumers()

    # producers =
    #   [{Sample.Producer, [workers: 3]}]
    #   |> Topology.producers()

    producers = []
    consumers = []

    [ConnectionManager]
    |> Enum.concat(producers)
    |> Enum.concat(consumers)
    |> Supervisor.start_link(strategy: :one_for_one, name: @name)
  end
end
