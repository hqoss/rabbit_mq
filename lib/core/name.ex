defmodule Core.Name do
  @spec random_id() :: String.t()
  def random_id, do: Nanoid.generate_non_secure(12)
  def child_spec_id, do: random_id() |> String.to_atom()

  @spec unique_worker_name(String.t()) :: atom()
  def unique_worker_name(module_name) when is_binary(module_name) do
    module_name
    |> String.split("/")
    |> List.last()
    |> Kernel.<>("_worker_")
    |> Kernel.<>(random_id())
    |> String.to_atom()
  end

  @spec module_to_snake_case(atom()) :: String.t()
  def module_to_snake_case(module) do
    module |> Macro.underscore()
  end
end
