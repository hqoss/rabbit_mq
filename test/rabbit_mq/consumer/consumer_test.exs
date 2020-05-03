defmodule RabbitMQTest.Consumer do
  alias AMQP.{Basic, Channel, Connection, Exchange, Queue}
  alias RabbitMQ.Consumer
  alias RabbitMQ.Consumer.Worker.State, as: ConsumerWorkerState

  use ExUnit.Case

  @amqp_url Application.get_env(:rabbit_mq, :amqp_url)
  @exchange "#{__MODULE__}"
  @routing_key "test.consumer"

  setup_all do
    assert {:ok, connection} = Connection.open(@amqp_url)
    assert {:ok, channel} = Channel.open(connection)

    # Ensure we have a disposable exchange set up.
    assert :ok = Exchange.declare(channel, @exchange, :topic, durable: false)

    # Declare a queue and bind it to the above exchange exchange.
    {:ok, %{queue: queue}} = Queue.declare(channel, "")
    :ok = Queue.bind(channel, queue, @exchange, routing_key: @routing_key)

    # Clean up after all tests have ran.
    on_exit(fn ->
      # Ensure there are no messages left hanging in the queue as it gets deleted.
      assert {:ok, %{message_count: 0}} = Queue.delete(channel, queue)

      assert :ok = Exchange.delete(channel, @exchange)
      assert :ok = Channel.close(channel)
      assert :ok = Connection.close(connection)
    end)

    [channel: channel, connection: connection, queue: queue]
  end

  setup %{channel: channel, queue: queue} do
    correlation_id = UUID.uuid4()

    on_exit(fn ->
      # Ensure there are no messages in the queue as the next test is about to start.
      assert true = Queue.empty?(channel, queue)
    end)

    [correlation_id: correlation_id]
  end

  describe "#{__MODULE__}" do
    test "defines correctly configured child specification" do
      defmodule TestConsumer do
        use Consumer, queue: "test_queue"

        def consume(_payload, meta, channel), do: ack(channel, meta.delivery_tag)
      end

      assert %{
               id: TestConsumer,
               restart: :permanent,
               shutdown: :brutal_kill,
               start:
                 {Consumer, :start_link,
                  [
                    %{consume_cb: _, prefetch_count: 10, queue: "test_queue", worker_count: 3},
                    [name: TestConsumer, opt: :extra_opt]
                  ]},
               type: :supervisor
             } = TestConsumer.child_spec(opt: :extra_opt)
    end

    test "establishes a connection and starts the defined number of workers", %{queue: queue} do
      config = %{
        consume_cb: fn _payload, meta, channel -> Basic.ack(channel, meta.delivery_tag) end,
        prefetch_count: 10,
        queue: queue,
        worker_count: 2
      }

      assert {:ok, pid} = Consumer.start_link(config, [])

      assert %Consumer.State{
               connection: %Connection{} = connection,
               workers: [worker_1, worker_2]
             } = :sys.get_state(pid)

      assert true === Process.alive?(connection.pid)

      assert {0, worker_1_pid, _worker_1_config} = worker_1
      assert {1, worker_2_pid, _worker_2_config} = worker_2

      assert worker_1_pid !== worker_2_pid

      assert :ok = GenServer.stop(pid)
    end

    test "workers are assigned their own channels from a shared connection", %{queue: queue} do
      config = %{
        consume_cb: fn _payload, meta, channel -> Basic.ack(channel, meta.delivery_tag) end,
        prefetch_count: 10,
        queue: queue,
        worker_count: 2
      }

      assert {:ok, pid} = Consumer.start_link(config, [])

      assert %Consumer.State{
               connection: %Connection{} = connection,
               workers: [
                 {0, worker_1_pid, _worker_1_config},
                 {1, worker_2_pid, _worker_2_config}
               ]
             } = :sys.get_state(pid)

      assert %ConsumerWorkerState{
               channel: %Channel{} = worker_1_channel
             } = :sys.get_state(worker_1_pid)

      assert %ConsumerWorkerState{
               channel: %Channel{} = worker_2_channel
             } = :sys.get_state(worker_2_pid)

      # The channels are different as they are specific to each worker.
      assert worker_1_channel.pid !== worker_2_channel.pid

      # The connections are the same as they originate in the same parent.
      assert worker_1_channel.conn === worker_2_channel.conn
      assert Enum.random([worker_1_channel.conn, worker_2_channel.conn]) === connection

      assert :ok = GenServer.stop(pid)
    end

    test "if a worker dies, it is re-started with a new channel, and its original channel is closed",
         %{queue: queue} do
      config = %{
        consume_cb: fn _payload, meta, channel -> Basic.ack(channel, meta.delivery_tag) end,
        prefetch_count: 10,
        queue: queue,
        worker_count: 2
      }

      assert {:ok, pid} = Consumer.start_link(config, [])

      assert %Consumer.State{
               connection: connection,
               workers: [
                 {0, _worker_1_pid, _worker_1_config},
                 {1, worker_2_pid, _worker_2_config}
               ]
             } = :sys.get_state(pid)

      Process.exit(worker_2_pid, :kill)

      # Wait until a new worker is spawned.
      :timer.sleep(5)

      assert %Consumer.State{
               connection: ^connection,
               workers: [
                 {0, _worker_1_pid, _worker_1_config},
                 {1, worker_3_pid, _worker_3_config}
               ]
             } = :sys.get_state(pid)

      assert worker_2_pid !== worker_3_pid

      assert :ok = GenServer.stop(pid)
    end

    test "if a connection dies, the entire Consumer pool re-starts", %{queue: queue} do
      supervisor = __MODULE__.Supervisor
      supervised_consumer = __MODULE__.SupervisedConsumer

      config = %{
        consume_cb: fn _payload, meta, channel -> Basic.ack(channel, meta.delivery_tag) end,
        prefetch_count: 10,
        queue: queue,
        worker_count: 2
      }

      children = [
        %{
          id: supervisor,
          start: {Consumer, :start_link, [config, [name: supervised_consumer]]}
        }
      ]

      assert {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

      consumer = Process.whereis(supervised_consumer)

      assert %Consumer.State{
               connection: connection,
               workers: workers
             } = :sys.get_state(consumer)

      Process.exit(connection.pid, :kill)

      # Wait until the child is re-started.
      :timer.sleep(5)

      new_consumer = Process.whereis(supervised_consumer)

      assert consumer !== new_consumer

      assert %Consumer.State{
               connection: new_connection,
               workers: new_workers
             } = :sys.get_state(new_consumer)

      assert connection.pid !== new_connection.pid
      assert workers !== new_workers

      assert :ok = Supervisor.stop(pid)
    end

    test "sets up an exclusive queue if requested", %{
      channel: channel,
      correlation_id: correlation_id
    } do
      # Capture current process pid to send a message to when `consume_cb` is called.
      test_pid = self()
      routing_key = "test.consumer.exclusive"

      config = %{
        consume_cb: fn payload, meta, channel ->
          send(test_pid, {payload, meta})
          Basic.ack(channel, meta.delivery_tag)
        end,
        prefetch_count: 1,
        queue: {@exchange, routing_key},
        worker_count: 1
      }

      assert {:ok, pid} = Consumer.start_link(config, [])

      assert :ok =
               Basic.publish(channel, @exchange, routing_key, "msg",
                 correlation_id: correlation_id
               )

      assert_receive({"msg", %{correlation_id: ^correlation_id}})

      assert :ok = GenServer.stop(pid)
    end
  end
end
