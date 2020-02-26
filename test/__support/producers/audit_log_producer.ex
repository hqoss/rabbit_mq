defmodule MQTest.Support.Producers.AuditLogProducer do
  use MQ.Producer, exchange: "audit_log"

  @valid_types ~w(login logout change_password update_profile)a

  @spec publish_event(String.t(), atom(), keyword()) :: :ok
  def publish_event(user_id, type, opts)
      when is_binary(user_id)
      when type in @valid_types and is_list(opts) do
    routing_key = routing_key(type)
    payload = payload(user_id)

    opts = opts |> Keyword.put(:routing_key, routing_key)

    publish(payload, opts)
  end

  defp payload(user_id), do: %{user_id: user_id} |> Jason.encode!()

  defp routing_key(:login), do: "user_action.login"
  defp routing_key(:logout), do: "user_action.logout"
  defp routing_key(:change_password), do: "user_action.change_password"
  defp routing_key(:update_profile), do: "user_action.update_profile"
end
