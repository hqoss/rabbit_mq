defmodule MQTest.Support.TestProducer do
  use MQ.Producer, exchange: "test"

  def publish_event(payload, opts \\ []) when is_binary(payload) and is_list(opts) do
    publish(payload, opts)
  end
end
