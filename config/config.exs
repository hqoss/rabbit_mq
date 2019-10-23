# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :logger, :console,
  level: :info,
  format: {Core.LogFormatter, :format},
  metadata: :all

config :logger, handle_otp_reports: false

config :rabbitex, :config,
  amqp_url: "amqp://guest:guest@localhost:5672",
  exchanges: Examples.Exchanges

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env()}.exs"
