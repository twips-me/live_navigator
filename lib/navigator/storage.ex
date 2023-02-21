defmodule Navigator.Storage do
  @moduledoc """
  Navigator storage behaviour
  """

  alias Navigator.Page

  @type cleanup_key :: {Navigator.session_id, Navigator.tab}

  @callback update([Navigator.t | Page.t]) :: :ok
  @callback select(Navigator) :: [Navigator.t]
  @callback select(Page) :: [Page.t]
  @callback cleanup([cleanup_key]) :: :ok
  @callback touch(Navigator | Page, list) :: :ok

  @app :navigator
  @storage Application.compile_env(@app, :storage)

  if is_nil(@storage) do
    @spec update([Navigator.t | Page.t]) :: :ok
    def update(_entities), do: :ok

    @spec select(Navigator) :: [Navigator.t]
    @spec select(Page) :: [Page.t]
    def select(_table), do: []

    @spec cleanup([cleanup_key]) :: :ok
    def cleanup(_keys), do: :ok

    @spec touch(Navigator | Page, list) :: :ok
    def touch(_table, _keys), do: :ok
  else
    @spec update([Navigator.t | Page.t]) :: :ok
    defdelegate update(entities), to: @storage

    @spec select(Navigator) :: [Navigator.t]
    @spec select(Page) :: [Page.t]
    defdelegate select(table), to: @storage

    @spec cleanup([cleanup_key]) :: :ok
    defdelegate cleanup(keys), to: @storage

    @spec touch(Navigator | Page, list) :: :ok
    defdelegate touch(table, keys), to: @storage
  end
end
