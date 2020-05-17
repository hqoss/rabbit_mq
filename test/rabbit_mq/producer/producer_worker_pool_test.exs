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

  @base_worker_pool_opts [
    connection: @connection,
    exchange: @exchange,
    name: @worker_pool,
    worker: @worker,
    worker_count: @worker_count
  ]

  setup_all do
    assert {:ok, _pid} = start_supervised({RabbitMQ.Connection, [name: @connection]})

    # Declare worker_pool_opts with default publisher confirm callbacks.
    worker_pool_opts =
      @base_worker_pool_opts
      |> Keyword.put(:handle_publisher_ack_confirms, fn _ -> :ok end)
      |> Keyword.put(:handle_publisher_nack_confirms, fn _ -> :ok end)

    [worker_pool_opts: worker_pool_opts]
  end

  test "start_link/1 starts a supervised worker pool with correctly named children", %{
    worker_pool_opts: worker_pool_opts
  } do
    assert {:ok, _pid} = start_supervised({WorkerPool, worker_pool_opts})

    assert [
             {2, worker_2, :worker, [RabbitMQ.Producer.Worker]},
             {1, worker_1, :worker, [RabbitMQ.Producer.Worker]},
             {0, worker_0, :worker, [RabbitMQ.Producer.Worker]}
           ] = Supervisor.which_children(@worker_pool)

    assert worker_0 === Process.whereis(Module.concat(@worker, "0"))
    assert worker_1 === Process.whereis(Module.concat(@worker, "1"))
    assert worker_2 === Process.whereis(Module.concat(@worker, "2"))
  end

  test "children use correctly configured exchange", %{worker_pool_opts: worker_pool_opts} do
    assert {:ok, _pid} = start_supervised({WorkerPool, worker_pool_opts})

    # Pick a random child (index)
    child_id = 0..2 |> Enum.random() |> Integer.to_string()

    assert %Worker.State{
             exchange: @exchange
           } = @worker |> Module.concat(child_id) |> :sys.get_state()
  end

  test "children use correctly configured publisher confirm callbacks", %{
    worker_pool_opts: worker_pool_opts
  } do
    assert {:ok, _pid} = start_supervised({WorkerPool, worker_pool_opts})

    handle_publisher_ack_confirms =
      Keyword.fetch!(worker_pool_opts, :handle_publisher_ack_confirms)

    handle_publisher_nack_confirms =
      Keyword.fetch!(worker_pool_opts, :handle_publisher_nack_confirms)

    # Pick a random child (index)
    child_id = 0..2 |> Enum.random() |> Integer.to_string()

    assert %Worker.State{
             exchange: @exchange,
             handle_publisher_ack_confirms: ^handle_publisher_ack_confirms,
             handle_publisher_nack_confirms: ^handle_publisher_nack_confirms
           } = @worker |> Module.concat(child_id) |> :sys.get_state()
  end

  test "children re-use the same connection", %{worker_pool_opts: worker_pool_opts} do
    assert {:ok, _pid} = start_supervised({WorkerPool, worker_pool_opts})

    assert %Connection{pid: connection_pid} = GenServer.call(@connection, :get)

    # Pick a random child (index)
    child_id = 0..2 |> Enum.random() |> Integer.to_string()

    assert %Worker.State{
             channel: %Channel{conn: %{pid: ^connection_pid}}
           } = @worker |> Module.concat(child_id) |> :sys.get_state()
  end
end
