defmodule RabbitMQTest.Connection do
  use AMQP
  use ExUnit.Case

  @connection __MODULE__

  describe "#{__MODULE__}" do
    test "establishes a connection" do
      assert {:ok, pid} = start_supervised({RabbitMQ.Connection, [name: @connection]})
      %Connection{pid: connection_pid} = :sys.get_state(pid)
      assert true === Process.alive?(connection_pid)
    end

    test "get/1 retrieves a connection" do
      assert {:ok, pid} = start_supervised({RabbitMQ.Connection, [name: @connection]})
      assert %Connection{} = connection = RabbitMQ.Connection.get(@connection)
      assert connection === :sys.get_state(pid)
    end

    test "when supervised, gets restarted when a connection dies" do
      children = [{RabbitMQ.Connection, [name: @connection]}]
      {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

      # Ensure the connection is alive.
      assert connection = RabbitMQ.Connection.get(@connection)
      assert true === Process.alive?(connection.pid)

      # Kill the connection.
      assert true === Process.exit(connection.pid, :broker_down)

      # Get a new connection, ensure it's alive.
      assert connection_2 = RabbitMQ.Connection.get(@connection)
      assert true === Process.alive?(connection_2.pid)

      assert :ok = Supervisor.stop(pid)
    end

    test "terminate closes the connection" do
      children = [{RabbitMQ.Connection, [name: @connection]}]
      {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

      assert %Connection{pid: connection_pid} =
               @connection |> Process.whereis() |> :sys.get_state()

      assert true === Process.alive?(connection_pid)

      assert :ok = Supervisor.terminate_child(pid, RabbitMQ.Connection)

      assert false === Process.alive?(connection_pid)

      assert :ok = Supervisor.stop(pid)
    end
  end
end
