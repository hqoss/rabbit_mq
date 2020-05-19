defmodule RabbitMQTest.Consumer do
  alias RabbitMQ.Consumer

  use AMQP
  use ExUnit.Case

  defmodule ConsumerWithCallback do
    @queue "#{__MODULE__}"
    @prefetch_count :rand.uniform(10)
    @worker_count :rand.uniform(8)

    use Consumer, prefetch_count: @prefetch_count, queue: @queue, worker_count: @worker_count

    def queue, do: @queue
    def prefetch_count, do: @prefetch_count
    def worker_count, do: @worker_count

    def handle_message(_data, _meta, _channel), do: :ok
  end

  @amqp_url Application.get_env(:rabbit_mq, :amqp_url)

  @exchange "#{__MODULE__}"
  @routing_key :crypto.strong_rand_bytes(16) |> Base.encode16()

  @connection __MODULE__.Connection
  @name __MODULE__
  @prefetch_count :rand.uniform(10)
  @worker_count :rand.uniform(8)
  @worker_pool __MODULE__.WorkerPool

  @base_opts [
    connection: @connection,
    name: @name,
    prefetch_count: @prefetch_count,
    queue: {@exchange, @routing_key},
    worker_count: @worker_count,
    worker_pool: @worker_pool
  ]

  setup_all do
    assert {:ok, connection} = Connection.open(@amqp_url)
    assert {:ok, channel} = Channel.open(connection)

    # Ensure we have a disposable exchange set up.
    assert :ok = Exchange.declare(channel, @exchange, :direct, durable: false)

    # Clean up after all tests have ran.
    on_exit(fn ->
      assert :ok = Exchange.delete(channel, @exchange)
      assert :ok = Channel.close(channel)
      assert :ok = Connection.close(connection)
    end)

    :ok
  end

  setup do
    test_pid = self()

    # Declare opts with a default consume callback.
    opts =
      @base_opts
      |> Keyword.put(:consume_cb, fn data, meta, channel ->
        Basic.ack(channel, meta.delivery_tag)
        send(test_pid, {data, meta})
      end)

    [opts: opts]
  end

  test "start_link/1 starts a named Supervisor with a dedicated connection, and a worker pool", %{
    opts: opts
  } do
    assert {:ok, pid} = start_supervised({Consumer, opts})

    assert {:state, {:local, @name}, :rest_for_one,
            {[:worker_pool, :connection],
             %{
               connection:
                 {:child, _connection_pid, :connection,
                  {RabbitMQ.Connection, :start_link,
                   [[max_channels: @worker_count, name: @connection]]}, :permanent, 5000, :worker,
                  [RabbitMQ.Connection]},
               worker_pool:
                 {:child, _worker_pool_pid, :worker_pool,
                  {:poolboy, :start_link,
                   [
                     [
                       name: {:local, @worker_pool},
                       worker_module: RabbitMQ.Consumer.Worker,
                       size: @worker_count,
                       max_overflow: 0
                     ],
                     [
                       connection: @connection,
                       consume_cb: consume_cb,
                       queue: {@exchange, @routing_key},
                       prefetch_count: @prefetch_count
                     ]
                   ]}, :permanent, :infinity, :supervisor, [:poolboy]}
             }}, :undefined, 3, 5, [], 0, RabbitMQ.Consumer, ^opts} = :sys.get_state(pid)

    assert consume_cb === opts[:consume_cb]
  end

  test "max_workers/0 retrieves the :max_channels_per_connection config" do
    assert Application.get_env(:rabbit_mq, :max_channels_per_connection, 8) ===
             Consumer.max_workers()
  end

  test "when used, child_spec/1 returns correctly configured child specification" do
    queue = ConsumerWithCallback.queue()
    prefetch_count = ConsumerWithCallback.prefetch_count()
    worker_count = ConsumerWithCallback.worker_count()

    assert %{
             id: ConsumerWithCallback,
             start:
               {RabbitMQ.Consumer, :start_link,
                [
                  [
                    connection: ConsumerWithCallback.Connection,
                    consume_cb: consume_cb,
                    name: ConsumerWithCallback,
                    queue: ^queue,
                    prefetch_count: ^prefetch_count,
                    worker_count: ^worker_count,
                    worker_pool: ConsumerWithCallback.WorkerPool
                  ]
                ]},
             type: :supervisor
           } = ConsumerWithCallback.child_spec([])

    assert :ok = consume_cb.(nil, nil, nil)
  end
end
