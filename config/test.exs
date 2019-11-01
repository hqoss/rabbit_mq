use Mix.Config

config :rabbitex, :config,
  amqp_url: "amqp://guest:guest@localhost:5672",
  topology: MQTest.Support.Topology
