defmodule RabbitMQTest.Producer do
  alias AMQP.{Channel, Connection}
  alias RabbitMQ.Producer
  alias RabbitMQ.Producer.Worker.State, as: ProducerWorkerState

  use ExUnit.Case

  @exchange "#{__MODULE__}"

  describe "#{__MODULE__}" do
    test "defines correctly configured child specification" do
      defmodule TestProducer do
        use Producer, exchange: "test_exchange"

        def on_publisher_nack(_), do: :ok
      end

      assert %{
               id: TestProducer,
               restart: :permanent,
               shutdown: :brutal_kill,
               start:
                 {Producer, :start_link,
                  [
                    %{
                      confirm_type: :async,
                      exchange: "test_exchange",
                      nack_cb: _,
                      worker_count: 3
                    },
                    [name: TestProducer, opt: :extra_opt]
                  ]},
               type: :supervisor
             } = TestProducer.child_spec(opt: :extra_opt)
    end

    test "establishes a connection and starts the defined number of workers" do
      config = %{
        confirm_type: :async,
        exchange: @exchange,
        nack_cb: fn _ -> :ok end,
        worker_count: 2
      }

      assert {:ok, pid} = Producer.start_link(config, [])

      assert %Producer.State{
               connection: %Connection{} = connection,
               workers: [worker_1, worker_2],
               worker_count: 2,
               worker_offset: 0
             } = :sys.get_state(pid)

      assert true === Process.alive?(connection.pid)

      assert {0, worker_1_pid, _worker_1_config} = worker_1
      assert {1, worker_2_pid, _worker_2_config} = worker_2

      assert worker_1_pid !== worker_2_pid

      assert :ok = GenServer.stop(pid)
    end

    test "workers are assigned their own channels from a shared connection" do
      config = %{
        confirm_type: :async,
        exchange: @exchange,
        nack_cb: fn _ -> :ok end,
        worker_count: 2
      }

      assert {:ok, pid} = Producer.start_link(config, [])

      assert %Producer.State{
               connection: %Connection{} = connection,
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

      assert :ok = GenServer.stop(pid)
    end

    test "if a worker dies, it is re-started with a new channel, and its original channel is closed" do
      config = %{
        confirm_type: :async,
        exchange: @exchange,
        nack_cb: fn _ -> :ok end,
        worker_count: 2
      }

      assert {:ok, pid} = Producer.start_link(config, [])

      assert %Producer.State{
               connection: connection,
               workers: [
                 {0, _worker_1_pid, _worker_1_config},
                 {1, worker_2_pid, _worker_2_config}
               ]
             } = :sys.get_state(pid)

      Process.exit(worker_2_pid, :kill)

      # Wait until a new worker is spawned.
      :timer.sleep(5)

      assert %Producer.State{
               connection: ^connection,
               workers: [
                 {0, _worker_1_pid, _worker_1_config},
                 {1, worker_3_pid, _worker_3_config}
               ]
             } = :sys.get_state(pid)

      assert worker_2_pid !== worker_3_pid

      assert :ok = GenServer.stop(pid)
    end

    test "if a connection dies, the entire Producer pool re-starts" do
      supervisor = __MODULE__.Supervisor
      supervised_producer = __MODULE__.SupervisedProducer

      config = %{
        confirm_type: :async,
        exchange: @exchange,
        nack_cb: fn _ -> :ok end,
        worker_count: 2
      }

      children = [
        %{
          id: supervisor,
          start: {Producer, :start_link, [config, [name: supervised_producer]]}
        }
      ]

      assert {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

      producer = Process.whereis(supervised_producer)

      assert %Producer.State{
               connection: connection,
               workers: workers
             } = :sys.get_state(producer)

      Process.exit(connection.pid, :kill)

      # Wait until the child is re-started.
      :timer.sleep(5)

      new_producer = Process.whereis(supervised_producer)

      assert producer !== new_producer

      assert %Producer.State{
               connection: new_connection,
               workers: new_workers
             } = :sys.get_state(new_producer)

      assert connection.pid !== new_connection.pid
      assert workers !== new_workers

      assert :ok = Supervisor.stop(pid)
    end

    test "publishing occurs in a round-robin fashion" do
      config = %{
        confirm_type: :async,
        exchange: @exchange,
        nack_cb: fn _ -> :ok end,
        worker_count: 3
      }

      assert {:ok, pid} = Producer.start_link(config, [])

      assert %Producer.State{
               workers: [
                 {_, worker_1_pid, _},
                 {_, worker_2_pid, _},
                 {_, worker_3_pid, _}
               ],
               worker_count: 3,
               worker_offset: 0
             } = :sys.get_state(pid)

      assert {:ok, worker_1_pid} === GenServer.call(pid, :get_producer_pid)

      assert %Producer.State{
               worker_count: 3,
               worker_offset: 1
             } = :sys.get_state(pid)

      assert {:ok, worker_2_pid} === GenServer.call(pid, :get_producer_pid)

      assert %Producer.State{
               worker_count: 3,
               worker_offset: 2
             } = :sys.get_state(pid)

      assert {:ok, worker_3_pid} === GenServer.call(pid, :get_producer_pid)

      assert %Producer.State{
               worker_count: 3,
               worker_offset: 3
             } = :sys.get_state(pid)

      assert {:ok, worker_1_pid} === GenServer.call(pid, :get_producer_pid)

      assert %Producer.State{
               worker_count: 3,
               worker_offset: 4
             } = :sys.get_state(pid)

      assert :ok = GenServer.stop(pid)
    end
  end
end
