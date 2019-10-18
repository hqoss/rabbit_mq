defmodule MQ.Support.ExclusiveQueue do
  @moduledoc """
  Use to create exclusive queues in tests.
  """

  alias AMQP.{Basic, Queue}
  alias MQ.ConnectionManager

  @this_module __MODULE__

  @spec declare(list()) :: {:ok, String.t()} | Basic.error()
  def declare(opts \\ []) when is_list(opts) do
    {:ok, channel} = ConnectionManager.request_channel(@this_module)

    queue = opts |> Keyword.get(:queue, "")
    exchange = opts |> Keyword.fetch!(:exchange)
    routing_key = opts |> Keyword.fetch!(:routing_key)

    with {:ok, %{queue: queue}} <- channel |> assert_queue(queue),
         :ok <- channel |> bind_queue(queue, exchange, routing_key),
         do: {:ok, queue}
  end

  defp assert_queue(channel, queue) do
    channel |> Queue.declare(queue, durable: false, exclusive: true)
  end

  defp bind_queue(channel, queue, exchange, routing_key) do
    channel |> Queue.bind(queue, exchange, routing_key: routing_key)
  end
end
