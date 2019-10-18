defmodule MQ.Support.TestConsumer do
  alias Core.Name
  alias MQ.Consumer
  alias MQ.Support.TestConsumerRegistry

  @this_module __MODULE__

  def child_spec(opts) do
    :ok = TestConsumerRegistry.init()

    consumer_tag = Name.random_id()
    pid = opts |> Keyword.fetch!(:pid)

    :ok = TestConsumerRegistry.register_pid(consumer_tag, pid)

    opts =
      opts
      |> Keyword.take([:queue])
      |> Keyword.merge(
        consumer_tag: consumer_tag,
        module: @this_module,
        prefetch_count: 1
      )

    %{
      id: consumer_tag,
      start: {Consumer, :start_link, [opts]}
    }
  end

  def process_message(payload, %{consumer_tag: consumer_tag} = meta) do
    {:ok, pid} = TestConsumerRegistry.lookup_pid(consumer_tag)

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
