defmodule AccountNumber do
  @sort_code "040638"
  @weight "13439317554524"
  @weight_table @weight |> String.codepoints() |> Enum.map(&String.to_integer/1)

  def find_next(last_id) when is_integer(last_id) do
    next_id = last_id + 1
    account_number = String.pad_leading("#{next_id}", 8, "0")

    case is_valid?(account_number) do
      true -> {next_id, @sort_code, account_number}
      _ -> find_next(next_id)
    end
  end

  defp is_valid?(account_number) do
    "#{@sort_code}#{account_number}"
    |> String.codepoints()
    |> Stream.map(&String.to_integer/1)
    |> Stream.with_index()
    |> Stream.map(fn {value, index} -> value * Enum.at(@weight_table, index) end)
    |> Stream.flat_map(fn
      value when value > 9 -> Integer.digits(value)
      value -> [value]
    end)
    |> Enum.sum()
    |> rem(10)
    |> Kernel.===(0)
  end
end
