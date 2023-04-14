defmodule LiveNavigator.Storage do
  @moduledoc """
  LiveNavigator storage behaviour
  """

  alias LiveNavigator.Page

  @type cleanup_key :: {LiveNavigator.session_id, LiveNavigator.tab}

  @callback update([LiveNavigator.t | Page.t]) :: :ok
  @callback select(LiveNavigator) :: [LiveNavigator.t]
  @callback select(Page) :: [Page.t]
  @callback cleanup([cleanup_key]) :: :ok
  @callback touch(LiveNavigator | Page, list) :: :ok

  @app :live_navigator
  @storage Application.compile_env(@app, :storage)

  if is_nil(@storage) do
    @spec update([LiveNavigator.t | Page.t]) :: :ok
    def update(_entities), do: :ok

    @spec select(LiveNavigator) :: [LiveNavigator.t]
    @spec select(Page) :: [Page.t]
    def select(_table), do: []

    @spec cleanup([cleanup_key]) :: :ok
    def cleanup(_keys), do: :ok

    @spec touch(LiveNavigator | Page, list) :: :ok
    def touch(_table, _keys), do: :ok
  else
    @spec update([LiveNavigator.t | Page.t]) :: :ok
    def update(entities), do: @storage.update(entities)

    @spec select(LiveNavigator) :: [LiveNavigator.t]
    @spec select(Page) :: [Page.t]
    def select(table), do: @storage.select(table)

    @spec cleanup([cleanup_key]) :: :ok
    def cleanup(keys), do: @storage.cleanup(keys)

    @spec touch(LiveNavigator | Page, list) :: :ok
    def touch(table, keys), do: @storage.touch(table, keys)
  end
end
