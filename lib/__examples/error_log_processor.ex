defmodule Examples.Processors.ErrorLogProcessor do
  require Logger

  def process_message(message, meta) do
    Logger.info("Processing...")
    :timer.sleep(7_500)
    Logger.info("Acknowledged.")

    :ok
  end
end
