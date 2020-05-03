defmodule RabbitMQTest.Producer.Worker do
  alias AMQP.{Basic, Channel, Connection, Exchange, Queue}
  alias RabbitMQ.Producer.Worker

  require Logger

  use ExUnit.Case

  @amqp_url Application.get_env(:rabbit_mq, :amqp_url)
  @exchange "#{__MODULE__}"

  setup_all do
    assert {:ok, connection} = Connection.open(@amqp_url)
    assert {:ok, channel} = Channel.open(connection)

    # Ensure we have a disposable exchange set up.
    assert :ok = Exchange.declare(channel, @exchange, :topic, durable: false)

    # Declare an exclusive queue and bind it to the above exchange.
    {:ok, %{queue: queue}} = Queue.declare(channel, "", exclusive: true)
    :ok = Queue.bind(channel, queue, @exchange, routing_key: "#")

    # Clean up after all tests have ran.
    on_exit(fn ->
      # This queue would have been deleted automatically when the connection
      # gets closed, however we manually delete it to avoid any naming conflicts
      # in between tests, no matter how unlikely. Also, we ensure there are no
      # messages left hanging in the queue.
      assert {:ok, %{message_count: 0}} = Queue.delete(channel, queue)

      assert :ok = Exchange.delete(channel, @exchange)
      assert :ok = Channel.close(channel)
      assert :ok = Connection.close(connection)
    end)

    [channel: channel, queue: queue]
  end

  setup %{channel: channel, queue: queue} do
    on_exit(fn ->
      # Ensure there are no messages in the queue as the next test is about to start.
      assert true = Queue.empty?(channel, queue)
    end)

    [
      channel: channel,
      correlation_id: UUID.uuid4()
    ]
  end

  describe "#{__MODULE__}" do
    test "is capable of publishing correctly configured payloads", %{
      channel: channel,
      correlation_id: correlation_id,
      queue: queue
    } do
      assert {:ok, pid} =
               start_supervised(
                 {Worker,
                  %{
                    channel: channel,
                    confirm_type: :async,
                    nack_cb: fn _ -> :ok end
                  }}
               )

      # This process will now start receiving events.
      assert {:ok, consumer_tag} = Basic.consume(channel, queue)

      # This will always be the first message received by the process.
      assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

      opts = [correlation_id: correlation_id]

      assert {:ok, seq_no} =
               GenServer.call(pid, {:publish, @exchange, "routing_key", "data", opts})

      assert_receive(
        {:basic_deliver, "data",
         %{
           consumer_tag: ^consumer_tag,
           correlation_id: ^correlation_id,
           delivery_tag: ^seq_no,
           routing_key: "routing_key"
         }}
      )

      # Unsubscribe.
      Basic.cancel(channel, consumer_tag)

      # This will always be the last message received by the process.
      assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test "fails to publish if correlation_id is not provided in opts", %{
      channel: channel,
      queue: queue
    } do
      assert {:ok, pid} =
               start_supervised(
                 {Worker,
                  %{
                    channel: channel,
                    confirm_type: :async,
                    nack_cb: fn _ -> :ok end
                  }}
               )

      # This process will now start receiving events.
      assert {:ok, consumer_tag} = Basic.consume(channel, queue)

      # This will always be the first message received by the process.
      assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

      assert {:error, :correlation_id_missing} =
               GenServer.call(pid, {:publish, @exchange, "routing_key", "data", []})

      # Unsubscribe
      Basic.cancel(channel, consumer_tag)

      # This will always be the last message received by the process.
      assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test ":basic_ack/:basic_nack in single mode deletes a specific outstanding confirm", %{
      channel: channel
    } do
      mode = Enum.random([:basic_ack, :basic_nack])

      state = %Worker.State{
        channel: channel,
        nack_cb: fn _ -> :ok end,
        outstanding_confirms: []
      }

      outstanding_confirms = [{42, "data", "routing_key", []}]

      assert {:noreply,
              %Worker.State{
                outstanding_confirms: []
              }} =
               Worker.handle_info({mode, 42, false}, %{
                 state
                 | outstanding_confirms: outstanding_confirms
               })

      outstanding_confirms = [
        {42, "data", "routing_key", []},
        {43, "data", "routing_key", []},
        {44, "data", "routing_key", []}
      ]

      assert {:noreply,
              %Worker.State{
                outstanding_confirms: [
                  {43, "data", "routing_key", []},
                  {44, "data", "routing_key", []}
                ]
              }} =
               Worker.handle_info({mode, 42, false}, %{
                 state
                 | outstanding_confirms: outstanding_confirms
               })

      outstanding_confirms = [
        {42, "data", "routing_key", []},
        {43, "data", "routing_key", []},
        {44, "data", "routing_key", []}
      ]

      assert {:noreply,
              %Worker.State{
                outstanding_confirms: [
                  {42, "data", "routing_key", []},
                  {44, "data", "routing_key", []}
                ]
              }} =
               Worker.handle_info({mode, 43, false}, %{
                 state
                 | outstanding_confirms: outstanding_confirms
               })
    end

    test ":basic_ack/:basic_nack in multi mode deletes outstanding confirms up to seq_number", %{
      channel: channel
    } do
      mode = Enum.random([:basic_ack, :basic_nack])

      state = %Worker.State{
        channel: channel,
        nack_cb: fn _ -> :ok end,
        outstanding_confirms: []
      }

      outstanding_confirms = [
        {42, "data", "routing_key", []},
        {43, "data", "routing_key", []},
        {44, "data", "routing_key", []}
      ]

      assert {:noreply, %Worker.State{outstanding_confirms: []}} =
               Worker.handle_info({mode, 42, true}, %{
                 state
                 | outstanding_confirms: outstanding_confirms
               })

      assert {:noreply,
              %Worker.State{
                outstanding_confirms: [
                  {42, "data", "routing_key", []}
                ]
              }} =
               Worker.handle_info({mode, 43, true}, %{
                 state
                 | outstanding_confirms: outstanding_confirms
               })
    end

    test ":basic_nack in single mode calls nack_cb with confirmed events", %{
      channel: channel
    } do
      test_pid = self()

      state = %Worker.State{
        channel: channel,
        nack_cb: fn args -> send(test_pid, args) end,
        outstanding_confirms: [
          {42, "data", "routing_key", []}
        ]
      }

      assert {:noreply, %Worker.State{outstanding_confirms: []}} =
               Worker.handle_info({:basic_nack, 42, false}, state)

      # Ensure nack_cb got called.
      assert_receive([{42, "data", "routing_key", []}])

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test ":basic_nack in multi mode calls nack_cb with confirmed events", %{
      channel: channel
    } do
      test_pid = self()

      state = %Worker.State{
        channel: channel,
        nack_cb: fn args -> send(test_pid, args) end,
        outstanding_confirms: [
          {42, "data", "routing_key", []},
          {43, "data", "routing_key", []}
        ]
      }

      assert {:noreply, %Worker.State{outstanding_confirms: []}} =
               Worker.handle_info({:basic_nack, 42, true}, state)

      # Ensure nack_cb got called.
      assert_receive([
        {42, "data", "routing_key", []},
        {43, "data", "routing_key", []}
      ])

      # Ensure no further messages are received.
      refute_receive(_)
    end
  end
end
