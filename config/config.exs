import Config

config :logger, :console,
  level: :debug,
  metadata: :all

config :logger, handle_otp_reports: false

config :rabbit_mq_ex,
  heartbeat_interval_sec: 15,
  reconnect_interval_ms: 2500,
  max_channels_per_connection: 16

import_config "#{Mix.env()}.exs"
