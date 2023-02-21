defmodule Navigator.Page do
  @moduledoc """
  Application page state
  """

  @type changes :: [atom]
  @type field :: :session_id | :tab | :view | :action | :assigns

  @type t :: %__MODULE__{
    session_id: binary,
    tab: pos_integer,
    view: module,
    action: atom,
    assigns: map,
    __changed__: changes,
  }

  @enforce_keys ~w[session_id tab view action]a
  defstruct [:session_id, :tab, :view, :action, assigns: %{}, __changed__: []]

  @simple_fields ~w[session_id tab view action]a
  @complex_fields ~w[assigns]a

  @spec update(t, map | keyword) :: t
  @spec update(t, field, any) :: t
  def update(%__MODULE__{__changed__: changed} = page, field, value) when field in @simple_fields do
    case Map.get(page, field) do
      ^value -> page
      _ -> Map.put(%{page | __changed__: Enum.uniq([field | changed])}, field, value)
    end
  end
  def update(%__MODULE__{__changed__: changed} = page, field, value) when field in @complex_fields do
    Map.put(%{page | __changed__: Enum.uniq([field | changed])}, field, value)
  end
  def update(page, fields) do
    Enum.reduce(fields, page, fn {field, value}, page -> update(page, field, value) end)
  end
end
