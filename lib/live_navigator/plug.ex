defmodule LiveNavigator.Plug do
  @moduledoc """
  Phoenix plug that is necessary for LiveNavigator
  """

  @behaviour Plug

  import Plug.Conn

  @app :live_navigator
  @default_session_key @app

  @impl true
  def init(opts) do
    opts
    |> Enum.into(%{})
    |> Map.put_new(:session_key, Application.get_env(@app, :session_key, @default_session_key))
  end

  @impl true
  def call(conn, %{session_key: session_key}) do
    case conn |> fetch_session() |> get_session(session_key) do
      nil -> put_session(conn, session_key, gen_nav_id())
      _ -> conn
    end
  end

  defp gen_nav_id, do: 48 |> :crypto.strong_rand_bytes() |> Base.encode64()
end
