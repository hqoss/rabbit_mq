defmodule MQ.Supervisor do
  alias MQ.{ConnectionManager, ConsumerPool}

  use Supervisor

  @consumer_opts ~w(module workers prefetch_count queue)a
  @producer_opts ~w(module workers worker_overflow)a
  @this_module __MODULE__

  @spec start_link(list()) :: Supervisor.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    Supervisor.start_link(@this_module, opts, name: @this_module)
  end

  @impl true
  def init(opts) do
    consumers = opts |> Keyword.get(:consumers, []) |> consumer_child_specs()
    producers = opts |> Keyword.get(:producers, []) |> producer_child_specs()

    [ConnectionManager]
    |> Enum.concat(consumers)
    |> Enum.concat(producers)
    |> Supervisor.init(strategy: :one_for_one)
  end

  defp consumer_child_specs(consumer_configs) do
    consumer_configs
    |> Enum.map(fn {module, opts} ->
      opts
      |> Keyword.put(:module, module)
      |> Keyword.put_new(:workers, 3)
      |> Keyword.put_new(:prefetch_count, 3)
      |> Keyword.take(@consumer_opts)
      |> consumer_pool_child_spec()
    end)
  end

  defp producer_child_specs(producer_configs) do
    producer_configs
    |> Enum.map(fn {module, opts} ->
      opts
      |> Keyword.put(:module, module)
      |> Keyword.put_new(:workers, 3)
      |> Keyword.put_new(:worker_overflow, 0)
      |> Keyword.take(@producer_opts)
      |> producer_pool_child_spec(module)
    end)
  end

  defp consumer_pool_child_spec(opts),
    do: ConsumerPool.child_spec(opts)

  defp producer_pool_child_spec(opts, module),
    do: apply(module, :child_spec, [opts])
end
