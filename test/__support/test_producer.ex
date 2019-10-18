defmodule MQTest.Support.TestProducer do
  use MQ.Producer, exchange: "test"

  @allowed_opts [:headers, :routing_key]

  def publish_event(payload, opts \\ []) when is_binary(payload) and is_list(opts) do
    opts = opts |> Keyword.take(@allowed_opts)
    publish(payload, opts)
  end
end
