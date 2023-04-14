defmodule LiveNavigator.Component do
  @moduledoc """
  LiveNavigator functionality for `Phoenix.LiveComponent`
  """

  alias LiveNavigator.{Controller, History}
  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket

  @type url :: LiveNavigator.url
  @type view :: LiveNavigator.view
  @type action :: LiveNavigator.action

  defmacro __using__(_opts) do
    quote do
      import unquote(LiveView), except: [
        push_navigate: 2,
        push_patch: 2,
        push_redirect: 2,
        redirect: 2,
      ]
      import unquote(__MODULE__), only: [
        # TODO: remove assign-like functions for live componene
        assign_nav: 2,
        assign_nav: 3,
        assign_page: 2,
        assign_page: 3,
        clear_nav: 2,
        clear_page: 2,
        # EOF TODO
        current_url: 1,
        history: 1,
        history_put: 2,
        history_put: 3,
        history_put: 4,
        history_put: 5,
        nav_back: 1,
        nav_back: 2,
        nav_back_url: 1,
        nav_back_url: 2,
        nav_pop_stack: 1,
        nav_pop_stack: 2,
        nav_pop_stack_url: 1,
        push_navigate: 2,
        push_patch: 2,
        push_redirect: 2,
        redirect: 2,
      ]
    end
  end

  @spec push_navigate(Socket.t, keyword) :: Socket.t
  def push_navigate(%Socket{root_pid: pid} = socket, opts) when is_pid(pid) do
    if Keyword.has_key?(opts, :to), do: navigate_forward(pid, :navigate, opts)
    if opts[:navigate] != false do
      LiveView.push_navigate(socket, Keyword.take(opts, ~w[to]a))
    else
      socket
    end
  end
  def push_navigate(socket, opts), do: LiveView.push_navigate(socket, opts)

  @spec push_patch(Socket.t, keyword) :: Socket.t
  def push_patch(%Socket{root_pid: pid} = socket, opts) when is_pid(pid) do
    if Keyword.has_key?(opts, :to), do: navigate_forward(pid, :patch, opts)
    if opts[:navigate] != false do
      LiveView.push_patch(socket, Keyword.take(opts, ~w[to]a))
    else
      socket
    end
  end
  def push_patch(socket, opts), do: LiveView.push_patch(socket, opts)

  @doc deprecated: "Use push_navigate/2 instead"
  # Deprecate in 0.19
  @spec push_redirect(Socket.t, keyword) :: Socket.t
  def push_redirect(%Socket{root_pid: pid} = socket, opts) when is_pid(pid) do
    if Keyword.has_key?(opts, :to), do: navigate_forward(pid, :navigate, opts)
    if opts[:navigate] != false do
      LiveView.push_redirect(socket, Keyword.take(opts, ~w[to]a))
    else
      socket
    end
  end
  def push_redirect(socket, opts), do: LiveView.push_redirect(socket, opts)

  @spec redirect(Socket.t, keyword) :: Socket.t
  def redirect(%Socket{root_pid: pid} = socket, opts) when is_pid(pid) do
    if Keyword.has_key?(opts, :to), do: navigate_forward(pid, :redirect, opts)
    if opts[:navigate] != false do
      LiveView.redirect(socket, Keyword.take(opts, ~w[to]a))
    else
      socket
    end
  end
  def redirect(socket, opts), do: LiveView.redirect(socket, opts)

  @spec history_put(Socket.t, History.spec) :: Socket.t
  @spec history_put(Socket.t, History.spec, keyword) :: Socket.t
  @spec history_put(Socket.t, url, view) :: Socket.t
  @spec history_put(Socket.t, url, view, action | keyword) :: Socket.t
  @spec history_put(Socket.t, url, view, action, keyword) :: Socket.t
  def history_put(socket, %History{} = spec), do: history_put(socket, spec, [])
  def history_put(socket, url, view) when is_binary(url), do: history_put(socket, url, view, nil, [])
  def history_put(%Socket{root_pid: pid} = socket, spec, opts) do
    with_navigator(pid, socket, fn %{history: history} = navigator, socket ->
      history =
        if opts[:stacked] == true do
          History.put_stacked(history, spec)
        else
          History.put(history, spec)
        end
      LiveNavigator.update(navigator, history: history)
      notify_view(pid, [:navigator])
      socket
    end)
  end
  def history_put(socket, url, view, action) when is_atom(action), do: history_put(socket, url, view, action, [])
  def history_put(socket, url, view, action, opts) when is_binary(url) and is_atom(view) and is_atom(action) do
    history_put(socket, History.new(url, view, action), opts)
  end

  @spec nav_back(Socket.t) :: Socket.t
  @spec nav_back(Socket.t, LiveNavigator.back_index | keyword) :: Socket.t
  def nav_back(socket, opts \\ [])
  def nav_back(socket, to) when not is_list(to), do: nav_back(socket, to: to)
  def nav_back(%Socket{root_pid: pid} = socket, opts) do
    with_navigator(pid, socket, fn %{history: history} = navigator, socket ->
      {index, unstack} =
        case Keyword.fetch(opts, :to) do
          {:ok, %History{} = spec} -> {spec, false}
          {:ok, {%History{} = spec, unstack}} when is_boolean(unstack) -> {spec, unstack}
          {:ok, {index, unstack}} when (is_integer(index) or is_atom(index)) and is_boolean(unstack) -> {index, unstack}
          {:ok, index} when is_integer(index) or is_atom(index) -> {index, false}
          _ -> {-2, false}
        end
      navigator
      |> LiveNavigator.navigate_back(History.find(history, index), unstack)
      |> apply_awaiting(socket, opts[:navigate])
    end)
  end
  def nav_back(socket, _), do: socket

  @spec nav_pop_stack(Socket.t) :: Socket.t
  @spec nav_pop_stack(Socket.t, keyword) :: Socket.t
  def nav_pop_stack(socket, opts \\ [])
  def nav_pop_stack(%Socket{root_pid: pid} = socket, opts) do
    with_navigator(pid, socket, fn
      %LiveNavigator{history: history} = navigator, socket when length(history) >= 2 ->
        navigator
        |> LiveNavigator.navigate_back(History.stack_preceding(history), false)
        |> apply_awaiting(socket, opts[:navigate])

      %LiveNavigator{fallback_url: url} = navigator, socket ->
        navigator
        |> LiveNavigator.update(:history, [])
        |> Controller.save()
        LiveView.push_navigate(socket, to: LiveNavigator.url_path(url))
    end)
  end
  def nav_pop_stack(socket, _), do: socket

  @doc """
  Assigns value to page session

  > WARNING! `assign_page/3` does nothing with local live component assigns. It just updates page session.
  """
  @spec assign_page(Socket.t, atom, any) :: Socket.t
  def assign_page(%Socket{root_pid: pid} = socket, key, value) when is_pid(pid) and is_atom(key) do
    with_navigator(pid, socket, fn navigator, socket ->
      LiveNavigator.update_page_assigns(navigator, [{key, value}], [])
      notify_view(pid, [:page])
      socket
    end)
  end
  def assign_page(socket, _key, _value), do: socket

  @doc """

  """
  @spec assign_page(Socket.t, keyword | map) :: Socket.t
  def assign_page(%Socket{root_pid: pid} = socket, assigns) when is_pid(pid) do
    with_navigator(pid, socket, fn navigator, socket ->
      LiveNavigator.update_page_assigns(navigator, assigns, [])
      notify_view(pid, [:page])
      socket
    end)
  end
  def assign_page(socket, _assigns), do: socket

  @doc """

  """
  @spec assign_nav(Socket.t, atom, any) :: Socket.t
  def assign_nav(%Socket{root_pid: pid} = socket, key, value) when is_pid(pid) and is_atom(key) do
    with_navigator(pid, socket, fn navigator, socket ->
      LiveNavigator.update_nav_assigns(navigator, [{key, value}], [])
      notify_view(pid, [:navigator])
      socket
    end)
  end
  def assign_nav(socket, _key, _value), do: socket

  @doc """

  """
  @spec assign_nav(Socket.t, keyword | map) :: Socket.t
  def assign_nav(%Socket{root_pid: pid} = socket, assigns) when is_pid(pid) do
    with_navigator(pid, socket, fn navigator, socket ->
      LiveNavigator.update_nav_assigns(navigator, assigns, [])
      notify_view(pid, [:navigator])
      socket
    end)
  end
  def assign_nav(socket, _assigns), do: socket

  @doc """

  """
  @spec clear_page(Socket.t, atom | [atom]) :: Socket.t
  def clear_page(%Socket{root_pid: pid} = socket, keys) do
    with_navigator(pid, socket, fn navigator, socket ->
      LiveNavigator.update_page_assigns(navigator, [], keys)
      notify_view(pid, [:page])
      socket
    end)
  end
  def clear_page(socket, _keys) do
    socket
  end

  @doc """

  """
  @spec clear_nav(Socket.t, atom | [atom]) :: Socket.t
  def clear_nav(%Socket{root_pid: pid} = socket, keys) do
    with_navigator(pid, socket, fn navigator, socket ->
      LiveNavigator.update_nav_assigns(navigator, [], keys)
      notify_view(pid, [:navigator])
      socket
    end)
  end
  def clear_nav(socket, _keys) do
    socket
  end

  @doc """

  """
  @spec history(Socket.t) :: History.t
  def history(%Socket{root_pid: pid}) do
    case Controller.get_navigator(pid) do
      %LiveNavigator{history: history} -> history
      _ -> []
    end
  end
  def history(_), do: []

  @doc """

  """
  @spec navigator(Socket.t) :: LiveNavigator.t | nil
  def navigator(%Socket{root_pid: pid}), do: Controller.get_navigator(pid)
  def navigator(_), do: nil

  @doc """

  """
  @spec current_url(Socket.t) :: binary | nil
  def current_url(%Socket{root_pid: pid}) do
    case Controller.get_navigator(pid) do
      %LiveNavigator{url: url} -> url
      _ -> nil
    end
  end
  def current_url(_), do: nil

  @doc """

  """
  @spec nav_back_url(Socket.t) :: binary | nil
  @spec nav_back_url(Socket.t, History.index) :: binary | nil
  def nav_back_url(socket, index \\ -2)
  def nav_back_url(%Socket{root_pid: pid}, index) do
    case Controller.get_navigator(pid) do
      %LiveNavigator{history: history, fallback_url: fallback_url} ->
        case History.find(history, index) do
          %{url: url} -> LiveNavigator.url_path(url)
          _ -> fallback_url
        end

      _ ->
        nil
    end
  end
  def nav_back_url(_socket, _index), do: nil

  @doc """

  """
  @spec nav_pop_stack_url(Socket.t) :: binary | nil
  def nav_pop_stack_url(%Socket{root_pid: pid}) do
    case Controller.get_navigator(pid) do
      %LiveNavigator{history: history, fallback_url: fallback_url} ->
        case History.stack_preceding(history) do
          %{url: url} -> LiveNavigator.url_path(url)
          _ -> fallback_url
        end

      _ ->
        nil
    end
  end
  def nav_pop_stack_url(_socket), do: nil

  defp navigate_forward(pid, action, opts) do
    case Controller.get_navigator(pid) do
      %LiveNavigator{} = navigator -> LiveNavigator.navigate_forward(navigator, action, opts)
      _ -> :ok
    end
  end

  defp with_navigator(pid, socket, fun) do
    case Controller.get_navigator(pid) do
      %LiveNavigator{} = navigator -> fun.(navigator, socket)
      _ -> socket
    end
  end

  defp apply_awaiting(_navigator, socket, false), do: socket
  defp apply_awaiting(%{awaiting: {%{method: :patch}, to, _}}, socket, _) do
    LiveView.push_patch(socket, to: LiveNavigator.url_path(to))
  end
  defp apply_awaiting(%{awaiting: {%{method: :navigate}, to, _}}, socket, _) do
    LiveView.push_navigate(socket, to: LiveNavigator.url_path(to))
  end
  defp apply_awaiting(%{awaiting: {%{method: :redirect}, to, _}}, socket, _) do
    LiveView.redirect(socket, to: LiveNavigator.url_path(to))
  end

  defp notify_view(pid, updates) do
    send(pid, {LiveNavigator, :reload, updates})
  end
end
