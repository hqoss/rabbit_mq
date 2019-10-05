defmodule Examples.Producers.AuditLogProducer do
  use MQ.Producer, exchange: "log"

  @valid_types ~w(login, logout, change_password, update_profile)a

  def publish_event(user_id, type) when is_binary(user_id) when type in @valid_types do
    routing_key = routing_key(type)
    payload = payload(user_id)

    publish(payload, routing_key: routing_key)
  end

  defp payload(user_id), do: %{user_id: user_id} |> Jason.encode!()

  defp routing_key(:login), do: "action.login"
  defp routing_key(:logout), do: "action.logout"
  defp routing_key(:change_password), do: "action.change_password"
  defp routing_key(:update_profile), do: "action.update_profile"
end
