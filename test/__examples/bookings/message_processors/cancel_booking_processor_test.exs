defmodule BookingsTest.MessageProcessors.CancelBookingMessageProcessor do
  alias Bookings.MessageProcessors.CancelBookingMessageProcessor
  alias Bookings.Store

  use ExUnit.Case

  setup_all do
    assert {:ok, _pid} = start_supervised(Store)
    :ok
  end

  setup do
    attrs = %{
      date_time: DateTime.utc_now() |> DateTime.to_iso8601(),
      flight_number: Nanoid.generate_non_secure(),
      external_booking_id: UUID.uuid4()
    }

    {:ok, booking} = Store.insert(attrs)

    on_exit(fn ->
      Store.delete_all()
    end)

    [booking: booking]
  end

  describe "Bookings.MessageProcessors.CancelBookingMessageProcessor.process_message/2" do
    test "cancels an existing booking and removes it from `Bookings.Store`", %{booking: booking} do
      payload = %{booking_id: booking.id}
      payload_binary = Jason.encode!(payload)

      assert :ok = CancelBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:error, :not_found} = Store.get_existing(booking.id)
    end

    test "returns `{:error, :invalid_payload}` if JSON payload is incomplete", %{booking: booking} do
      payload = %{unimportant_key: Nanoid.generate_non_secure()}
      payload_binary = Jason.encode!(payload)

      assert {:error, :invalid_payload} =
               CancelBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, _booking} = Store.get_existing(booking.id)
    end

    test "returns `{:error, %Jason.DecodeError{}}` if JSON payload is invalid", %{
      booking: booking
    } do
      payload_binary = "Hey, boss!"

      assert {:error, %Jason.DecodeError{}} =
               CancelBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, _booking} = Store.get_existing(booking.id)
    end

    test "returns `{:error, :not_found}` if booking not found in `Bookings.Store`", %{
      booking: booking
    } do
      payload = %{booking_id: UUID.uuid4()}
      payload_binary = Jason.encode!(payload)

      assert {:error, :not_found} =
               CancelBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, _booking} = Store.get_existing(booking.id)
    end
  end
end
