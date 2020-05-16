defmodule RabbitMQTest.Producer.WorkerPool do
  alias RabbitMQ.Producer.Worker
  alias RabbitMQ.Producer.WorkerPool

  use AMQP
  use ExUnit.Case

  @exchange "#{__MODULE__}"

  @connection __MODULE__.Connection
  @worker __MODULE__.Worker
  @worker_count 3
  @worker_pool __MODULE__

  @producer_worker_opts [
    connection: @connection,
    exchange: @exchange,
    name: @worker_pool,
    worker: @worker,
    worker_count: @worker_count
  ]

  setup_all do
    assert {:ok, _pid} = start_supervised({RabbitMQ.Connection, [name: @connection]})
    :ok
  end

  test "start_link/1 starts a supervised worker pool with correctly named children" do
    assert {:ok, _pid} = start_supervised({WorkerPool, @producer_worker_opts})

    assert [
             {2, worker_2, :worker, [RabbitMQ.Producer.Worker]},
             {1, worker_1, :worker, [RabbitMQ.Producer.Worker]},
             {0, worker_0, :worker, [RabbitMQ.Producer.Worker]}
           ] = Supervisor.which_children(@worker_pool)

    assert worker_0 === Process.whereis(Module.concat(@worker, "0"))
    assert worker_1 === Process.whereis(Module.concat(@worker, "1"))
    assert worker_2 === Process.whereis(Module.concat(@worker, "2"))
  end

  test "all worker pool children use correctly configured exchange" do
    assert {:ok, _pid} = start_supervised({WorkerPool, @producer_worker_opts})

    # Pick a random child (index)
    child_id = 0..2 |> Enum.random() |> Integer.to_string()

    assert %Worker.State{
             exchange: @exchange
           } = @worker |> Module.concat(child_id) |> :sys.get_state()
  end

  test "all worker pool children re-use the same connection" do
    assert {:ok, _pid} = start_supervised({WorkerPool, @producer_worker_opts})

    assert %Connection{pid: connection_pid} = GenServer.call(@connection, :get)

    # Pick a random child (index)
    child_id = 0..2 |> Enum.random() |> Integer.to_string()

    assert %Worker.State{
             channel: %Channel{conn: %{pid: ^connection_pid}}
           } = @worker |> Module.concat(child_id) |> :sys.get_state()
  end
end
