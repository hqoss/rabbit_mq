use Mix.Config

config :rabbit_mq_ex, :config,
  amqp_url: "amqp://guest:guest@localhost:5672",
  topology: Bookings.Topology
