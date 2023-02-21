defmodule Navigator.History do
  @moduledoc """
  User navigation history
  """

  @type id :: pos_integer
  @type view :: module
  @type action :: atom
  @type url :: binary
  @type name :: atom
  @type index :: integer | name

  @typedoc """
  Specifies the page view. `:view` field stores the `Phoenix.LiveView` module
  of the page, `:action` contains the live view action which is usualy stored
  in `:live_action` assign, `:url` is the full URL of page and the `:name` is
  the page alias that can be specified in navigation-related functions (such
  as `push_patch/2` or `push_navigate/2`) with an `:as` option.
  """
  @type spec :: %__MODULE__{
    id: id,
    view: view,
    action: action,
    url: url,
    name: name | nil,
  }

  @type t :: [spec | [spec]]

  @enforce_keys ~w[id view action url]a
  defstruct ~w[id view action url name]a

  @spec new(Navigator.t) :: spec
  @spec new(Navigator.t, name) :: spec
  @spec new(url, view, action) :: spec
  @spec new(url, view, action, name) :: spec
  def new(%Navigator{} = navigator, name \\ nil) do
    fields =
      navigator
      |> Map.take(~w[url view action]a)
      |> Map.put(:name, name)
      |> Map.put(:id, generate_id())
    struct(__MODULE__, fields)
  end
  def new(url, view, action, name \\ nil) do
    %__MODULE__{
      id: generate_id(),
      view: view,
      action: action,
      url: url,
      name: name,
    }
  end

  @spec reverse(t) :: t
  def reverse(history) do
    history
    |> Enum.reverse()
    |> Enum.map(fn
      [_ | _] = stack -> Enum.reverse(stack)
      spec -> spec
    end)
  end

  @spec put(t, spec | [spec]) :: t
  def put(history, spec), do: [spec | history]

  @spec put_stacked(t, spec) :: t
  def put_stacked([[_ | _] = stack | history], spec), do: [[spec | stack] | history]
  def put_stacked(history, spec), do: [[spec] | history]

  @spec find(t, integer | name | url | spec) :: spec | nil
  def find(history, idx \\ -1)
  def find(_history, %__MODULE__{} = spec), do: spec
  def find(history, url) when is_binary(url), do: find_by_url(history, url)
  def find(history, idx) when not is_integer(idx), do: find_by_name(history, idx)
  def find(history, idx) when idx >= 0, do: find(reverse(history), -idx - 1)
  def find([[spec | _] | _], -1), do: spec
  def find([spec | _], -1), do: spec
  def find(_, -1), do: nil
  def find([[_ | _] = stack | rest], idx) do
    size = length(stack)
    if -idx > size do
      find(rest, idx + size)
    else
      Enum.at(stack, -idx - 1)
    end
  end
  def find([_ | rest], idx), do: find(rest, idx + 1)

  @spec stack_preceding(t) :: spec | nil
  def stack_preceding([_ | [[spec | _] | _]]), do: spec
  def stack_preceding([_ | [spec | _]]), do: spec
  def stack_preceding(_), do: nil

  @spec stack_top(t) :: spec | nil
  def stack_top([[_ | _] = stack | _]), do: List.first(stack)
  def stack_top(_), do: nil

  @spec replace(t, id, spec, boolean) :: t
  def replace(_history, 0, spec, _unstack), do: [spec]
  def replace([[%__MODULE__{id: id}] | rest], id, spec, false), do: [[spec] | rest]
  def replace([[%__MODULE__{id: id}] | rest], id, spec, true), do: [spec | rest]
  def replace([[%__MODULE__{id: id} | stack] | rest], id, spec, _unstack), do: [[spec | stack] | rest]
  def replace([[_ | stack] | rest], id, spec, unstack), do: replace([stack | rest], id, spec, unstack)
  def replace([%__MODULE__{id: id} | rest], id, spec, _unstack), do: [spec | rest]
  def replace([_ | rest], id, spec, unstack), do: replace(rest, id, spec, unstack)
  def replace(_history, _id, spec, _unstack), do: [spec]

  defp find_by_name([[%{name: name} = spec | _] | _], name), do: spec
  defp find_by_name([[_ | stack] | rest], name), do: find_by_name([stack | rest], name)
  defp find_by_name([%{name: name} = spec | _], name), do: spec
  defp find_by_name([_ | rest], name), do: find_by_name(rest, name)
  defp find_by_name(_history, _name), do: nil

  defp find_by_url([[%{url: url} = spec | _] | _], url), do: spec
  defp find_by_url([[_ | stack] | rest], url), do: find_by_url([stack | rest], url)
  defp find_by_url([%{url: url} = spec | _], url), do: spec
  defp find_by_url([_ | rest], url), do: find_by_url(rest, url)
  defp find_by_url(_history, _url), do: nil

  defp generate_id do
    <<id::unsigned-size(64)>> = :crypto.strong_rand_bytes(8)
    id + 1 # id shouldn't be == 0
  end
end
