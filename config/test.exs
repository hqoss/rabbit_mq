import Config

config :rabbit_mq_ex, :amqp_url, "amqp://guest:guest@localhost:5672"

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
   ]},
  {"audit_log",
   type: :topic,
   durable: true,
   routing_keys: [
     {"user_action.*",
      queue: "audit_log_queue/user_action.*/rabbit_mq_ex",
      durable: true,
      dlq: "audit_log_dead_letter_queue"}
   ]},
  {"service_request",
   type: :topic,
   durable: true,
   routing_keys: [
     {"#",
      queue: "service_request_queue/#/rabbit_mq_ex",
      durable: false,
      dlq: "service_request_dead_letter_queue"}
   ]}
]
