defmodule MQ.ConsumerPool do
  alias MQ.Consumer

  use Supervisor

  @this_module __MODULE__

  @spec start_link(list()) :: Supervisor.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    module = opts |> Keyword.fetch!(:module)

    # Consumer pools need to be named as there will often be more than one.
    Supervisor.start_link(@this_module, opts, name: module)
  end

  @spec child_spec(list()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) when is_list(opts) do
    module = opts |> Keyword.fetch!(:module)

    %{
      id: module,
      start: {@this_module, :start_link, [opts]},
      type: :supervisor
    }
  end

  @impl true
  def init(opts) do
    workers = opts |> Keyword.fetch!(:workers)

    1..workers
    |> Enum.map(&consumer_worker_child_spec(&1, opts))
    |> Supervisor.init(strategy: :one_for_one)
  end

  defp consumer_worker_child_spec(index, opts) when is_list(opts) do
    %{
      id: index,
      start: {Consumer, :start_link, [opts]}
    }
  end
end
