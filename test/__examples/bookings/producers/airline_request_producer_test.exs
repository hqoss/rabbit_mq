defmodule BookingsTest.Producers.AirlineRequestProducer do
  alias MQ.ConnectionManager
  alias MQTest.Support.{RabbitCase, ExclusiveQueue, TestConsumer}
  alias Bookings.Producers.AirlineRequestProducer

  use RabbitCase

  setup_all do
    assert {:ok, _pid} = start_supervised(AirlineRequestProducer.child_spec())

    # Make sure our tests receive all messages published to the `airline_request`
    # exchange, regardless of the `routing_key` configured (hence `#`).
    assert {:ok, airline_request_queue} =
             ExclusiveQueue.declare(exchange: "airline_request", routing_key: "#")

    # Start the `TestConsumer` module, which consumes messages from a given queue
    # and sends them to a process associated with a test that's being executed.
    #
    # See `TestConsumer.register_reply_to(self())` in the `setup` section below.
    assert {:ok, _pid} = start_supervised(TestConsumer.child_spec(queue: airline_request_queue))

    :ok
  end

  setup do
    # Each test process will register its pid (`self()`) so that we can receive
    # corresponding payloads and metadata published via the `Producer`(s).
    assert {:ok, reply_to} = TestConsumer.register_reply_to(self())

    # Each registration generates a unique identifier which will be used
    # in the `TestConsumer`'s message processor module to look up the pid
    # of the currently running test and send the payload and the metadata
    # to that process.
    publish_opts = [reply_to: reply_to]

    [publish_opts: publish_opts]
  end

  describe "Bookings.Producers.AirlineRequestProducer" do
    test "place_booking/3 only accepts `qatar_airways` and `british_airways` booking requests", %{
      publish_opts: publish_opts
    } do
      payload = %{
        date_time: DateTime.utc_now() |> DateTime.to_iso8601(),
        flight_number: Nanoid.generate_non_secure()
      }

      assert :ok = AirlineRequestProducer.place_booking(:british_airways, payload, publish_opts)
      assert :ok = AirlineRequestProducer.place_booking(:qatar_airways, payload, publish_opts)

      assert_receive({:json, %{}, %{routing_key: "british_airways.place_booking"}}, 250)
      assert_receive({:json, %{}, %{routing_key: "qatar_airways.place_booking"}}, 250)
    end

    test "place_booking/3 produces a message with default metadata", %{publish_opts: publish_opts} do
      date_time = DateTime.utc_now() |> DateTime.to_iso8601()
      flight_number = "QR007"
      payload = %{date_time: date_time, flight_number: flight_number}

      assert :ok = AirlineRequestProducer.place_booking(:qatar_airways, payload, publish_opts)

      assert_receive(
        {:json, %{"date_time" => ^date_time, "flight_number" => ^flight_number},
         %{routing_key: "qatar_airways.place_booking"} = meta},
        250
      )

      assert {:ok, _details} = UUID.info(meta.correlation_id)
      refute meta.timestamp == :undefined

      refute_receive 100
    end

    test "place_booking/3 produces a message with custom metadata, but does not override `routing_key`",
         %{publish_opts: publish_opts} do
      date_time = DateTime.utc_now() |> DateTime.to_iso8601()
      flight_number = "QR007"
      payload = %{date_time: date_time, flight_number: flight_number}

      correlation_id = UUID.uuid4()
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:second)

      publish_opts =
        publish_opts
        |> Keyword.merge(
          app_id: "bookings_app",
          correlation_id: correlation_id,
          headers: [{"authorization", "Bearer abc.123"}],
          routing_key: "unsupported_airline.unsupported_action",
          timestamp: timestamp
        )

      assert :ok = AirlineRequestProducer.place_booking(:qatar_airways, payload, publish_opts)

      assert_receive(
        {:json, %{"date_time" => ^date_time, "flight_number" => ^flight_number},
         %{routing_key: "qatar_airways.place_booking"} = meta},
        250
      )

      assert meta.app_id == "bookings_app"
      assert meta.correlation_id == correlation_id
      assert meta.headers == [{"authorization", :longstr, "Bearer abc.123"}]
      assert meta.timestamp == timestamp
    end

    test "cancel_booking/3 only accepts `qatar_airways` and `british_airways` booking cancellation requests",
         %{
           publish_opts: publish_opts
         } do
      payload = %{booking_id: Nanoid.generate_non_secure()}

      assert :ok = AirlineRequestProducer.cancel_booking(:british_airways, payload, publish_opts)
      assert :ok = AirlineRequestProducer.cancel_booking(:qatar_airways, payload, publish_opts)

      assert_receive({:json, %{}, %{routing_key: "british_airways.cancel_booking"}}, 250)
      assert_receive({:json, %{}, %{routing_key: "qatar_airways.cancel_booking"}}, 250)
    end

    test "cancel_booking/3 produces a message with default metadata", %{
      publish_opts: publish_opts
    } do
      booking_id = UUID.uuid4()
      payload = %{booking_id: booking_id}

      assert :ok = AirlineRequestProducer.cancel_booking(:qatar_airways, payload, publish_opts)

      assert_receive(
        {:json, %{"booking_id" => ^booking_id},
         %{routing_key: "qatar_airways.cancel_booking"} = meta},
        250
      )

      assert {:ok, _details} = UUID.info(meta.correlation_id)
      refute meta.timestamp == :undefined

      refute_receive 100
    end

    test "cancel_booking/3 produces a message with custom metadata, but does not override `routing_key`",
         %{publish_opts: publish_opts} do
      booking_id = UUID.uuid4()
      payload = %{booking_id: booking_id}

      correlation_id = UUID.uuid4()
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:second)

      publish_opts =
        publish_opts
        |> Keyword.merge(
          app_id: "bookings_app",
          correlation_id: correlation_id,
          headers: [{"authorization", "Bearer abc.123"}],
          routing_key: "unsupported_airline.unsupported_action",
          timestamp: timestamp
        )

      assert :ok = AirlineRequestProducer.cancel_booking(:qatar_airways, payload, publish_opts)

      assert_receive(
        {:json, %{"booking_id" => ^booking_id},
         %{routing_key: "qatar_airways.cancel_booking"} = meta},
        250
      )

      assert meta.app_id == "bookings_app"
      assert meta.correlation_id == correlation_id
      assert meta.headers == [{"authorization", :longstr, "Bearer abc.123"}]
      assert meta.timestamp == timestamp
    end
  end
end
