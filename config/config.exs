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

import_config "#{Mix.env()}.exs"
