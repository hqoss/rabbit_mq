defmodule Examples.Processors.AuditLogProcessor do
  require Logger

  def process_message(_message, _meta) do
    Logger.info("Processing...")
    :timer.sleep(7_500)
    Logger.info("Acknowledged.")

    :ok
  end
end
