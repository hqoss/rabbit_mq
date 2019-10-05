defmodule MQ.Topology.Setup do
  @moduledoc """
  Use to perform a one-off setup of exchanges
  and queues for `dev` and `test` environments.
  """

  alias AMQP.{
    Channel,
    Connection,
    Exchange,
    Queue
  }

  alias MQ.Topology.Config.{DeadLetterQueueConfig, QueueConfig, TopicExchangeConfig}

  require Logger

  @amqp_url "amqp://guest:guest@localhost:5672"

  defmodule Result do
    defstruct channel: nil, exchanges: [], errors: []
  end

  def run(topology) when is_list(topology) do
    with {:ok, connection} <- Connection.open(@amqp_url),
         {:ok, channel} <- Channel.open(connection),
         results <- channel |> setup(topology),
         :ok <- channel |> Channel.close() do
      {:ok, results}
    end
  end

  defp setup(channel, topology) do
    topology
    |> Task.async_stream(&setup_exchange(channel, &1))
    |> Enum.to_list()
  end

  defp setup_exchange(channel, %TopicExchangeConfig{
         name: exchange,
         durable: durable,
         queues: queues
       }) do
    channel
    |> assert_exchange(:topic, exchange, durable)
    |> setup_queues(queues)
  end

  defp setup_queues(channel, queues) when is_list(queues) do
    queues |> Enum.map(&setup_queues(channel, &1))
  end

  defp setup_queues(
         channel,
         {%DeadLetterQueueConfig{} = dead_letter_queue, %QueueConfig{} = queue}
       ) do
    channel
    |> assert_dead_letter_queue(dead_letter_queue)
    |> assert_queue(queue)
    |> bind_queue(queue)
  end

  defp assert_exchange(channel, :topic, name, durable) do
    :ok = channel |> Exchange.topic(name, durable: durable)
    channel
  end

  defp assert_dead_letter_queue(channel, %DeadLetterQueueConfig{name: name, durable: durable}) do
    {:ok, _} = channel |> Queue.declare(name, durable: durable)
    channel
  end

  defp assert_queue(channel, %QueueConfig{
         name: name,
         durable: durable,
         exclusive: exclusive,
         args: arguments
       }) do
    {:ok, %{queue: queue}} =
      channel |> Queue.declare(name, durable: durable, exclusive: exclusive, arguments: arguments)

    {channel, queue}
  end

  defp bind_queue({channel, queue}, %QueueConfig{binding: {exchange, "", routing_key}} = config) do
    :ok = channel |> Queue.bind(queue, exchange, routing_key: routing_key)
    result(queue, config)
  end

  defp bind_queue(
         {channel, queue},
         %QueueConfig{binding: {exchange, queue, routing_key}} = config
       ) do
    :ok = channel |> Queue.bind(queue, exchange, routing_key: routing_key)
    result(queue, config)
  end

  defp result(queue, %QueueConfig{binding: {exchange, _queue, routing_key}} = config) do
    config
    |> Map.take([:durable, :exclusive, :args])
    |> Map.merge(%{
      exchange: exchange,
      queue: queue,
      routing_key: routing_key
    })
  end
end
