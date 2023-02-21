defmodule Navigator.Lifecycle do
  @moduledoc false

  alias Phoenix.LiveView.Socket

  @spec __using__(keyword) :: Macro.t
  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :navigator_lifecycle, accumulate: true)
      import unquote(__MODULE__), only: [on_page_enter: 1, on_page_leave: 1, on_page_refresh: 1]
    end
  end

  @doc false
  @spec lifecycle(Macro.Env.t) :: keyword
  def lifecycle(%Macro.Env{module: module}) do
    Module.get_attribute(module, :navigator_lifecycle, [])
  end

  @spec on_page_refresh(Macro.t) :: Macro.t
  defmacro on_page_refresh(module) do
    module = parse_module(module, {:on_page_refresh, 2}, __CALLER__)
    quote do
      @navigator_lifecycle {:on_page_refresh, unquote(module)}
    end
  end

  @spec on_page_enter(Macro.t) :: Macro.t
  defmacro on_page_enter(module) do
    module = parse_module(module, {:on_page_enter, 4}, __CALLER__)
    quote do
      @navigator_lifecycle {:on_page_enter, unquote(module)}
    end
  end

  @spec on_page_leave(Macro.t) :: Macro.t
  defmacro on_page_leave(module) do
    module = parse_module(module, {:on_page_leave, 2}, __CALLER__)
    quote do
      @navigator_lifecycle {:on_page_leave, unquote(module)}
    end
  end

  @doc false
  @spec run_lifecycle(module, atom, list, Socket.t) :: {:cont | :halt, Socket.t}
  @spec run_lifecycle(module, atom, list, Navigator.t) :: {:cont | :halt, Navigator.t}
  def run_lifecycle(view, action, args, socket) do
    if function_exported?(view, :__navigator__, 1) do
      :lifecycle
      |> view.__navigator__()
      |> Enum.filter(& match?({^action, _}, &1))
      |> Enum.reduce_while({:cont, socket}, fn {_, mod}, {_, socket} ->
        if function_exported?(mod, action, length(args) + 1) do
          case apply(mod, action, args ++ [socket]) do
            {:cont, socket} -> {:cont, {:cont, socket}}
            {:halt, socket} -> {:halt, {:halt, socket}}
          end
        else
          {:cont, {:cont, socket}}
        end
      end)
    else
      {:cont, socket}
    end
  end

  defp parse_module(module, fun, caller) do
    if Macro.quoted_literal?(module) do
      Macro.prewalk(module, &expand_alias(&1, caller, fun))
    else
      module
    end
  end

  defp expand_alias({:__aliases__, _, _} = alias, env, fun), do: Macro.expand(alias, %{env | function: fun})
  defp expand_alias(other, _env, _fun), do: other
end
