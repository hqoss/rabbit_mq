defmodule TransactionConsumer do
  use RabbitMQ.Consumer, worker_count: 1, queue: "yo"

  def consume(payload, meta, channel) do
    Logger.info("Received #{payload}, meta: #{inspect(meta)}.")
    ack(channel, meta.delivery_tag) |> IO.inspect()
    :ok
  end
end
