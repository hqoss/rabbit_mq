defmodule Core.Name do
  @spec random_id() :: String.t()
  def random_id, do: :crypto.strong_rand_bytes(8) |> Base.encode64()
  def child_spec_id, do: random_id() |> String.to_atom()

  @spec unique_worker_name(atom()) :: atom()
  def unique_worker_name(name) when is_atom(name) do
    name
    |> Atom.to_string()
    |> Kernel.<>("_worker_")
    |> Kernel.<>(random_id())
    |> String.to_atom()
  end

  @spec module_to_snake_case(atom()) :: atom()
  def module_to_snake_case(module) do
    module |> Macro.underscore() |> String.to_atom()
  end
end
