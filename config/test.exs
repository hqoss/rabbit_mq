import Config

config :logger, handle_otp_reports: false

config :rabbit_mq_ex, :amqp_url, "amqp://guest:guest@localhost:5672"
