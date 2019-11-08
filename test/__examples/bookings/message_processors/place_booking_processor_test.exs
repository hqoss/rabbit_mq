defmodule BookingsTest.MessageProcessors.PlaceBookingMessageProcessor do
  alias Bookings.MessageProcessors.PlaceBookingMessageProcessor
  alias Bookings.Store

  use ExUnit.Case

  setup_all do
    assert {:ok, _pid} = start_supervised(Store)
    :ok
  end

  setup do
    on_exit(fn ->
      Store.delete_all()
    end)

    :ok
  end

  describe "Bookings.MessageProcessors.PlaceBookingMessageProcessor.process_message/2" do
    test "makes a new booking and places it into `Bookings.Store`" do
      payload = %{
        date_time: DateTime.utc_now() |> DateTime.to_iso8601(),
        flight_number: Nanoid.generate_non_secure()
      }

      payload_binary = Jason.encode!(payload)

      assert :ok = PlaceBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, [{id, booking}]} = Store.get_all()

      assert booking.id == id
      assert booking.date_time == payload.date_time
      assert booking.flight_number == payload.flight_number
      assert is_binary(booking.external_booking_id) == true
      assert is_integer(booking.inserted_at) == true
    end

    test "returns `{:error, :invalid_payload}` if JSON payload is incomplete" do
      payload = %{
        flight_number: Nanoid.generate_non_secure()
      }

      payload_binary = Jason.encode!(payload)

      assert {:error, :invalid_payload} =
               PlaceBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, []} = Store.get_all()
    end

    test "returns `{:error, %Jason.DecodeError{}}` if JSON payload is invalid" do
      payload_binary = "Hey, boss!"

      assert {:error, %Jason.DecodeError{}} =
               PlaceBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, []} = Store.get_all()
    end

    test "returns `{:error, :invalid_format}` if `date_time` is invalid" do
      payload = %{
        date_time: "invalid date time",
        flight_number: Nanoid.generate_non_secure()
      }

      payload_binary = Jason.encode!(payload)

      assert {:error, :invalid_format} =
               PlaceBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, []} = Store.get_all()
    end
  end
end
