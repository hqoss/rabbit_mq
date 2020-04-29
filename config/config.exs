import Config

config :logger, :console,
  level: :debug,
  format: {Core.LogFormatter, :format},
  metadata: :all

config :rabbit_mq_ex,
  amqp_url: "amqp://guest:guest@localhost:5672",
  heartbeat_interval_sec: 15,
  reconnect_interval_ms: 2500,
  max_channels_per_connection: 16

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
