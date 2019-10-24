defmodule MQTest.Support.Consumers.AuditLogMessageProcessor do
  def process_message(_payload, _meta) do
    :ok
  end
end
