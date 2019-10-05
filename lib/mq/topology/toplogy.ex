defmodule MQ.Topology.Config do
  defmodule DeadLetterQueueConfig do
    @enforce_keys [:name]
    defstruct name: nil, durable: true, exclusive: false
  end

  defmodule QueueConfig do
    @enforce_keys [:name, :durable, :exclusive, :binding, :args]
    defstruct name: nil, durable: nil, exclusive: nil, binding: nil, args: nil
  end

  defmodule TopicExchangeConfig do
    @enforce_keys [:name, :durable, :queues]
    defstruct name: nil, durable: nil, type: :topic, queues: nil
  end

  def gen(exchanges) when is_list(exchanges) do
    exchanges |> Enum.map(&exchange_config/1)
  end

  defp exchange_config({exchange, opts}) do
    type = opts |> Keyword.get(:type, :topic)
    exchange_config(exchange, type, opts)
  end

  defp exchange_config(exchange, :topic, opts) do
    durable = opts |> Keyword.get(:durable, true)
    routing_keys = opts |> Keyword.get(:routing_keys, [])
    queues = routing_keys |> Enum.map(&queue_config(exchange, &1))

    %TopicExchangeConfig{name: exchange, durable: durable, queues: queues}
  end

  defp queue_config(exchange, {routing_key, opts}) do
    queue = opts |> Keyword.get(:queue, "")
    durable = opts |> Keyword.get(:durable, true)
    exclusive = opts |> Keyword.get(:exclusive, false)
    dlq = opts |> Keyword.get(:dlq, "dead_letter_queue")

    dead_letter_queue_config = %DeadLetterQueueConfig{name: dlq}

    queue_config = %QueueConfig{
      name: queue,
      durable: durable,
      exclusive: exclusive,
      args: dlq_args(dead_letter_queue_config),
      binding: {exchange, queue, routing_key}
    }

    {dead_letter_queue_config, queue_config}
  end

  def dlq_args(%DeadLetterQueueConfig{name: dlq}) do
    [
      {"x-dead-letter-exchange", :longstr, ""},
      {"x-dead-letter-routing-key", :longstr, dlq}
    ]
  end
end
