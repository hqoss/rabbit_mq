defmodule TransactionProducer do
  use RabbitMQ.Producer, exchange: "", worker_count: 3

  def hold(client_id, amount, transaction_id)
      when is_binary(client_id) and is_float(amount) and is_binary(transaction_id) do
    :ok =
      publish(
        "Hold -#{amount}; Client #{client_id}; Transaction #{transaction_id}",
        "holds.authorized",
        correlation_id: transaction_id
        # persistent: true
        # mandatory: true
      )
  end
end
