defmodule CustomerProducer do
  use RabbitMQ.Producer, exchange: "customer", worker_count: 3

  @supported_types ~w(debug info warn error)a

  def created(customer_id) do
    correlation_id = 24 |> :crypto.strong_rand_bytes() |> Base.encode64()

    # TODO look at the behaviour with persistent: true, mandatory: true
    opts = [correlation_id: correlation_id]

    publish("Customer #{customer_id} created.", "customer.created", opts)
  end

  def update(customer_id, data \\ %{}) do
    correlation_id = 24 |> :crypto.strong_rand_bytes() |> Base.encode64()

    # TODO look at the behaviour with persistent: true, mandatory: true
    opts = [correlation_id: correlation_id]

    publish(
      "Customer #{customer_id} update. Update patch #{inspect(data)}",
      "customer.updated",
      opts
    )
  end
end
