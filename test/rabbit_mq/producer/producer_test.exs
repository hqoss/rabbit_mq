defmodule RabbitMQTest.Producer do
  alias AMQP.{Channel, Connection}
  alias RabbitMQ.Producer
  alias RabbitMQ.Producer.Worker.State, as: ProducerWorkerState

  use ExUnit.Case

  describe "Producer" do
    defmodule TestProducer do
      @exchange "#{__MODULE__}"
      use Producer, exchange: @exchange, worker_count: 2
      def exchange, do: @exchange
    end

    test "defines correctly configured child specification" do
      exchange = TestProducer.exchange()

      assert %{
               id: TestProducer,
               restart: :permanent,
               shutdown: :infinity,
               start:
                 {RabbitMQ.Producer, :start_link,
                  [
                    %{confirm_type: :async, exchange: ^exchange, worker_count: 2},
                    [name: TestProducer, opt: :extra_opt]
                  ]},
               type: :supervisor
             } = TestProducer.child_spec(opt: :extra_opt)
    end

    test "establishes a connection and starts the defined number of workers" do
      assert {:ok, pid} = start_supervised(TestProducer)

      assert %Producer.State{
               connection: %Connection{} = connection,
               worker_count: 2,
               workers: [worker_1, worker_2]
             } = :sys.get_state(pid)

      assert true = Process.alive?(connection.pid)

      assert {0, worker_1_pid, _worker_1_config} = worker_1
      assert {1, worker_2_pid, _worker_2_config} = worker_2

      assert worker_1_pid !== worker_2_pid
    end

    test "workers are assigned their own channels from a shared connection" do
      assert {:ok, pid} = start_supervised(TestProducer)

      assert %Producer.State{
               connection: %Connection{} = connection,
               worker_count: 2,
               workers: [
                 {0, worker_1_pid, _worker_1_config},
                 {1, worker_2_pid, _worker_2_config}
               ]
             } = :sys.get_state(pid)

      assert %ProducerWorkerState{
               channel: %Channel{} = worker_1_channel
             } = :sys.get_state(worker_1_pid)

      assert %ProducerWorkerState{
               channel: %Channel{} = worker_2_channel
             } = :sys.get_state(worker_2_pid)

      # The channels are different as they are specific to each worker.
      assert worker_1_channel.pid !== worker_2_channel.pid

      # The connections are the same as they originate in the same parent.
      assert worker_1_channel.conn === worker_2_channel.conn
      assert Enum.random([worker_1_channel.conn, worker_2_channel.conn]) === connection
    end

    test "if a worker dies, it is re-started with a new channel, and its original channel is closed" do
      assert {:ok, pid} = start_supervised(TestProducer)

      assert %Producer.State{
               connection: connection,
               worker_count: 2,
               workers: [
                 {0, _worker_1_pid, _worker_1_config},
                 {1, worker_2_pid, _worker_2_config}
               ]
             } = :sys.get_state(pid)

      Process.exit(worker_2_pid, :kill)

      # Wait until a new worker is spawned.
      :timer.sleep(25)

      assert %Producer.State{
               connection: ^connection,
               worker_count: 2,
               workers: [
                 {0, _worker_1_pid, _worker_1_config},
                 {1, worker_3_pid, _worker_3_config}
               ]
             } = :sys.get_state(pid)

      assert worker_2_pid !== worker_3_pid
    end

    test "if a connection dies, the entire Producer pool re-starts" do
      children = [
        TestProducer
      ]

      assert {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

      producer = Process.whereis(TestProducer)

      assert %Producer.State{
               connection: connection,
               workers: workers
             } = :sys.get_state(producer)

      Process.exit(connection.pid, :kill)

      # Wait until the child is re-started.
      :timer.sleep(25)

      new_producer = Process.whereis(TestProducer)

      assert producer !== new_producer

      assert %Producer.State{
               connection: new_connection,
               workers: new_workers
             } = :sys.get_state(new_producer)

      assert connection.pid !== new_connection.pid
      assert workers !== new_workers

      assert :ok = Supervisor.stop(pid)
    end
  end
end
