defmodule Bookings.Application do
  @moduledoc """
  Describes the entire produce/consume workflow.

  For demonstration purposes only!

  You would most likely structure your applications differently,
  for example the corresponding producers and consumers would
  live in separate services/apps. 
  """

  alias MQ.Supervisor, as: MQSupervisor

  alias Bookings.Producers.AirlineRequestProducer
  alias Bookings.Store

  alias Bookings.MessageProcessors.{
    CancelBookingMessageProcessor,
    PlaceBookingMessageProcessor
  }

  use Application

  def start(_type, _args) do
    opts = [
      consumers: [
        {PlaceBookingMessageProcessor,
         queue: "airline_request_queue/*.place_booking/bookings_app"},
        {CancelBookingMessageProcessor,
         queue: "airline_request_queue/*.cancel_booking/bookings_app"}
      ],
      producers: [
        AirlineRequestProducer
      ]
    ]

    children = [
      {MQSupervisor, opts},
      {Store, []}
      # ... add more children here
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
