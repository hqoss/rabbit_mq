defmodule RabbitMQ.Producer.WorkerPool do
  @moduledoc """
  Starts given number of workers under a `Supervisor`.
  """

  alias RabbitMQ.Producer.Worker

  use Supervisor

  @this_module __MODULE__

  @worker_pool_opts ~w(connection exchange handle_publisher_ack handle_publisher_nack worker worker_count)a

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    worker_pool_opts = Keyword.take(opts, @worker_pool_opts)

    Supervisor.start_link(@this_module, worker_pool_opts, name: name)
  end

  @impl true
  def init(worker_pool_opts) do
    worker_count = Keyword.fetch!(worker_pool_opts, :worker_count)
    worker = Keyword.fetch!(worker_pool_opts, :worker)

    opts = Keyword.delete(worker_pool_opts, :worker_count)

    children =
      1..worker_count
      |> Enum.with_index()
      |> Enum.map(fn {_, index} ->
        opts = Keyword.put(opts, :name, Module.concat(worker, "#{index}"))

        %{
          id: index,
          start: {Worker, :start_link, [opts]}
        }
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
