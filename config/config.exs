# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :logger, :console,
  level: :info,
  format: {Core.LogFormatter, :format},
  metadata: :all

config :logger, handle_otp_reports: false

:logger.add_primary_filter(
  :ignore_rabbitmq_progress_reports,
  {&:logger_filters.domain/2, {:stop, :equal, [:progress]}}
)

config :rabbit_mq_ex, :topology, [
  {"airline_request",
   type: :topic,
   durable: true,
   routing_keys: [
     {"*.place_booking",
      queue: "airline_request_queue/*.place_booking/bookings_app",
      durable: true,
      dlq: "airline_request_dead_letter_queue"},
     {"*.cancel_booking",
      queue: "airline_request_queue/*.cancel_booking/bookings_app",
      durable: true,
      dlq: "airline_request_dead_letter_queue"}
   ]}
]

import_config "#{Mix.env()}.exs"
