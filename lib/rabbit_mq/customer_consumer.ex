defmodule CustomerConsumer do
  use RabbitMQ.Consumer, worker_count: 3, queue: "customer/customer.created"

  def consume(payload, meta, channel) do
    Logger.info("Received #{payload}, meta: #{inspect(meta)}.")
    ack(channel, meta.delivery_tag) |> IO.inspect(label: "ack result")
    :ok
  end
end
