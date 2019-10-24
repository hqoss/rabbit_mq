defmodule MQTest.Support.TestConsumer do
  alias Core.Name
  alias MQ.Consumer
  alias MQTest.Support.TestConsumerRegistry

  require Logger

  @this_module __MODULE__

  def child_spec(opts) do
    queue = opts |> Keyword.fetch!(:queue)

    opts =
      opts
      |> Keyword.take([:queue])
      |> Keyword.merge(
        module: @this_module,
        prefetch_count: 1
      )

    %{
      id: queue,
      start: {Consumer, :start_link, [opts]}
    }
  end

  def register_reply_to(consumer_pid) when is_pid(consumer_pid) do
    reply_to = Name.random_id()
    :ok = TestConsumerRegistry.register_pid(reply_to, consumer_pid)
    {:ok, reply_to}
  end

  def process_message(payload, %{reply_to: reply_to} = meta) do
    {:ok, pid} = TestConsumerRegistry.lookup_pid(reply_to)

    message =
      case Jason.decode(payload) do
        {:ok, decoded_message} ->
          {:json, decoded_message, meta}

        _ ->
          {:binary, payload, meta}
      end

    send(pid, message)

    :ok
  end
end
