defmodule LiveNavigator do
  @moduledoc """
  This library improves
  [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/) navigation and adds
  application state to your application. Often when user refreshes browser or
  presses back button you loose current live view state. Also when user
  navigates through live views you can't get this navigation path (for example
  from which page user reached current page). This library solves both of these
  problems.

  > WARNGING! The `0.1.x` version is not production ready yet. The nearest
  > production ready version would be `0.2.x`

  ## Usage

  Add library to dependencies

      {:live_navigator, "~> 0.1"}

  Add `LiveNavigator` to your application supervisor

      children = [
        ...
        LiveNavigator,
        ...
      ]

  Add `LiveNavigator.Plug` to your browser pipeline:

      defmodule YourWebApp.Router do
        pipeline :browser do
          ...
          LiveNavigator.Plug
        end
      end

  To detect different browser tabs LiveNavigator needs to run some code on the
  client side. So add the following to your `assets/package.json`:

  ```json
  "live_navigator": "file:../../../deps/live_navigator",
  ```

  And to your `assets/app.js`:

  ```js
  import { initNavigator } from './live_navigator';

  const liveSocket = new LiveSocket('/live', Socket, initNavigator({
    // your phoenix LiveSocket params here
  }));
  ```

  Then use `LiveNavigator` in your live views and `LiveNavigator.Component` in
  your live components (`LiveNavigator.Component` is necessary only in those
  components that are doing any kind of redirection or navigator/page
  assignments)

      defmodule YourWebApp.ExampleLive do
        use YourWebApp, :live_view
        use LiveNavigator
        ...
      end

      defmodule YourWebApp.Components.NavBar do
        use YourWebApp, :live_component
        use LiveNavigator.Component
        ...
      end

  In case you are going to use LiveNavigator for entire application it's better
  to place usage into your app definitions:

      defmodule YourWebApp do
        def liver_view do
          quote do
            use Phoenix.LiveView
            use LiveNavigator
          end
        end

        def live_component do
          quote do
            use Phoenix.LiveComponent
            use LiveNavigator.Component
          end
        end
      end

  Now you have few additional assign functions in your live views:
  `&assign_page/3`, `&assign_nav/3`, `&assign_page_new/3`, `&assign_nav_new/3`,
  `&clear_page/2` and `&clear_nav/3`. All of them works with assigns.
  LiveNavigator introduces two application states: navigator state and page
  state. Navigator state is a global application state that is unique for live
  views opened from deffierent browser tab and different HTTP session (that is
  set up via cookies usualy). Page state is a state that unique for different
  live view module and live view action and with above conditions for navigator
  state. In other words when user opens in browser one of your pages, lets say
  page `A` the new navigator and page states created. That he navigates to
  different page `B` new page state created (but page state `A` is not deleted).
  If he then backs to page `A` it's state will be loaded into your assigns.
  While navigator state stay same for all above operations. If user then opens
  any page in new browser tab then all states including navigator state will be
  created from sсratch.

  To control user navigation you now has several additional callbacks in your
  live views: `&handle_page_refresh/2`, `&handle_page_leave/4` and
  `&handle_page_enter/4`. `&handle_page_refresh/2` will be called if user
  refreshes browser and stay on the same page. `&handle_page_enter/4` called
  when user enters the page from other location. And `&handle_page_leave/4`
  called when user going to another location. Note that while
  `&handle_page_refresh/2` and `&handle_page_enter/4` are called before standard
  `handle_params` callback and executed in live view process, but
  `&handle_page_leave/4` called in process of live view where user went and the
  only save functions here is the assign-related functions provided by
  LiveNavigator.
  """

  alias IEx.History
  alias LiveNavigator.{Controller, History, Lifecycle, Page}
  alias Phoenix.{Component, LiveView}
  alias Phoenix.LiveView.Socket

  use Supervisor

  @type action_method :: :navigate | :patch | :redirect | :browse

  @type history_action :: :put | :stack | :stack_add | {:replace, History.index, boolean}

  @type back_index :: History.index | History.spec | {History.index | History.spec, boolean}

  @typedoc """

  """
  @type action_spec :: %{
    required(:method) => action_method,
    required(:action) => history_action,
    optional(:as) => History.name,
    optional(:to) => non_neg_integer | atom,
  }

  @type assign_new_callback :: (-> any) | (map -> any)

  @type session_id :: binary
  @type tab :: integer
  @type url :: binary
  @type view :: module
  @type action :: atom
  @type changes :: [atom]
  @type assigns :: map
  @type field :: :session_id | :tab | :url | :view | :action | :awaiting | :history | :assigns

  @type t :: %__MODULE__{
    session_id: session_id,
    tab: tab,
    url: url | nil,
    view: view | nil,
    action: action | nil,
    awaiting: tuple | nil,
    history: History.t,
    assigns: assigns,
    __changed__: changes,
  }

  @enforce_keys ~w[session_id tab]a
  defstruct [
    session_id: nil,
    tab: nil,
    url: nil,
    view: nil,
    action: nil,
    awaiting: nil,
    history: [],
    assigns: %{},
    __changed__: [],
  ]

  @doc """
  Called when user refreshes the page in browser. The first argument is the
  page view specification and the second is the socket. This function must
  return `{:noreply, Socket.t}` tuple.
  """
  @callback handle_page_refresh(History.spec, Socket.t) :: {:noreply, Socket.t}

  @doc """
  Called when user moves to this page from another. The first argument is the
  action that leaded the event (see `action_spec` for details), the second
  argument is the view specification of the page the user comes from, the
  third argument is the view specification of the page the user comes to
  (which is current view in this case) and the fourth is the socket. This
  function must return `{:noreply, Socket.t}` tuple.
  """
  @callback handle_page_enter(action_spec, History.spec | nil, History.spec, Socket.t) :: {:noreply, Socket.t}

  @doc """
  Called when user moves from another page to this one. This function unlike
  `&handle_page_refresh/2` and `&handle_page_enter/4` called from another
  process and have no access to socket. The only safe functions here is the
  assets-related functions provided by `LiveNavigator`. Arguments are the same
  as in `&handle_page_enter/4` except that the last argument is the
  `LiveNavigator` object instead of `Socket`. This function must return
  `{:noreply, LiveNavigator.t}` tuple
  """
  @callback handle_page_leave(action_spec, History.spec, History.spec, t) :: {:noreply, t}

  @app :live_navigator
  @session_key to_string(Application.compile_env(@app, :session_key, @app))
  # @tab_key to_string(Application.compile_env(@app, :tab_key, "_live_navigator_tab"))
  @navigator @app

  @spec start_link() :: Supervisor.on_start
  @spec start_link(keyword) :: Supervisor.on_start
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    children = [
      {Controller, opts},
    ]
    Supervisor.init(children, strategy: :one_for_all)
  end

  @spec __using__(any) :: Macro.t
  defmacro __using__(opts) do
    fallback_url = Keyword.get(opts, :fallback_url, "/")
    quote do
      @behaviour unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      @live_navigator_fallback_url unquote(fallback_url)

      import unquote(LiveView), except: [
        push_navigate: 2,
        push_patch: 2,
        push_redirect: 2,
        redirect: 2,
      ]
      import unquote(__MODULE__), only: [
        assign_nav: 2,
        assign_nav: 3,
        assign_nav_new: 3,
        assign_page: 2,
        assign_page: 3,
        assign_page_new: 3,
        clear_nav: 2,
        clear_page: 2,
        current_url: 1,
        fallback_url: 1,
        history: 1,
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
      on_mount unquote(__MODULE__)

      @impl unquote(__MODULE__)
      def handle_page_refresh(_view, socket), do: {:noreply, socket}

      @impl unquote(__MODULE__)
      def handle_page_enter(_action, _from, _to, socket), do: {:noreply, socket}

      @impl unquote(__MODULE__)
      def handle_page_leave(_action, _from, _to, nav), do: {:noreply, nav}

      defoverridable [
        handle_page_enter: 4,
        handle_page_leave: 4,
        handle_page_refresh: 2,
      ]
    end
  end

  @spec __before_compile__(Macro.Env.t) :: Macro.t
  defmacro __before_compile__(env) do
    lifecycle = Lifecycle.lifecycle(env)
    fallback_url = Module.get_attribute(env.module, :live_navigator_fallback_url)
    quote do
      def __navigator__(:lifecycle), do: unquote(lifecycle)
      def __navigator__(:fallback_url), do: unquote(fallback_url)
    end
  end

  @spec fallback_url(nil | atom | binary) :: Macro.t
  defmacro fallback_url(url) when is_nil(url) or is_atom(url) or is_binary(url) do
    quote do
      @live_navigator_fallback_url unquote(url)
    end
  end

  @spec on_mount(any, map, map, Socket.t) :: {:cont, Socket.t}
  def on_mount(_args, _params, %{@session_key => nav_id}, socket) when is_binary(nav_id) and byte_size(nav_id) > 0 do
    socket =
      socket
      |> put_navigator({nav_id, 0})
      |> attach_handle_params()
      |> attach_handle_info()
    {:cont, socket}
  end
  def on_mount(_args, _params, _session, socket) do
    {:cont, socket}
  end
  # def on_mount(_args, _params, session, socket) do
  #   socket =
  #     if LiveView.connected?(socket) do
  #       case {Map.get(session, to_string(@session_key)), LiveView.get_connect_params(socket)} do
  #         {nav_id, %{@tab_key => tab}} when is_binary(nav_id) and is_integer(tab) and tab > 0 ->
  #           socket
  #           |> put_navigator({nav_id, tab})
  #           |> attach_handle_params()
  #           |> attach_handle_info()

  #         _ ->
  #           socket
  #       end
  #     else
  #       socket
  #     end
  #   {:cont, socket}
  # end

  @spec handle_params(map, binary, Socket.t) :: {:cont | :halt, Socket.t}
  def handle_params(
    _params,
    url,
    %Socket{view: view, assigns: assigns, private: %{@navigator => navigator}} = socket
  ) do
    action = Map.get(assigns, :live_action)
    {navigator, page} =
      case navigator do
        {session_id, tab} when is_binary(session_id) and is_integer(tab) -> # and tab > 0 ->
          {
            Controller.load_navigator(session_id, tab),
            Controller.load_page(session_id, tab, view, action)
          }

        %__MODULE__{session_id: session_id, tab: tab} = navigator when is_binary(session_id) and is_integer(tab) ->
          {
            navigator,
            Controller.load_page(session_id, tab, view, action)
          }
      end
    %Socket{private: %{@navigator => navigator}} = socket =
      socket
      |> put_navigator(navigator)
      |> apply_assigns(navigator)
      |> apply_assigns(page)
    {navigator, actions} = checkout_navigator(navigator, url, view, action)
    socket = put_navigator(socket, navigator)
    case Enum.reduce_while(actions, socket, &run_callback/2) do
      %Socket{redirected: nil} = socket -> {:cont, socket}
      socket -> {:halt, socket}
    end
  end
  def handle_params(_params, _url, socket), do: {:cont, socket}

  def handle_info({__MODULE__, :reload, to_reload}, socket) do
    socket =
      Enum.reduce(to_reload, socket, fn
        :navigator, socket ->
          navigator = Controller.get_navigator()
          socket |> put_navigator(socket) |> apply_assigns(navigator)

        :page, socket ->
          apply_assigns(socket, Controller.get_page())
      end)
    {:halt, socket}
  end
  def handle_info(_, socket) do
    {:cont, socket}
  end

  def handle_event(
    "lv:put-awaiting",
    %{"method" => method, "to" => to} = params,
    %Socket{private: %{@navigator => %__MODULE__{} = navigator}} = socket
  ) when method in ~w[navigate patch] and is_binary(to) do
    method = String.to_existing_atom(method)
    opts = []
    opts =
      case params do
        %{"stack" => true} -> Keyword.put(opts, :stack, true)
        %{"stack" => "new"} -> Keyword.put(opts, :stack, :new)
        _ -> opts
      end
    opts =
      case params do
        %{"replace" => true} -> Keyword.put(opts, :replace, true)
        %{"replace" => idx} when is_integer(idx) -> Keyword.put(opts, :replace, idx)
        %{"replace" => name} when is_binary(name) -> Keyword.put(opts, :replace, String.to_existing_atom(name))
        _ -> opts
      end
    spec = push_action_spec(navigator, method, opts)
    put_awaiting(navigator, to, spec)
    {:halt, socket}
  end
  def handle_event("ln:back", params, socket) do
    unstack = Map.get(params, "unstack") == true
    opts =
      case params do
        %{"to" => to} when is_integer(to) -> [to: {to, unstack}]
        %{"to" => to} when is_binary(to) -> [to: {String.to_existing_atom(to), unstack}]
        _ -> []
      end
    {:halt, nav_back(socket, opts)}
  end
  def handle_event("ln:pop_stack", _params, socket) do
    {:halt, nav_pop_stack(socket, [])}
  end
  def handle_event(_event, _data, socket) do
    {:cont, socket}
  end

  @simple_fields ~w[session_id tab url view action]a
  @complex_fields ~w[awaiting history assigns]a

  @spec update(t, map | keyword) :: t
  @spec update(t, field, any) :: t
  def update(%__MODULE__{__changed__: changed} = navigator, field, value) when field in @simple_fields do
    case Map.get(navigator, field) do
      ^value -> navigator
      _ -> Map.put(%{navigator | __changed__: Enum.uniq([field | changed])}, field, value)
    end
  end
  def update(%__MODULE__{__changed__: changed} = navigator, field, value) when field in @complex_fields do
    Map.put(%{navigator | __changed__: Enum.uniq([field | changed])}, field, value)
  end
  def update(navigator, fields) do
    Enum.reduce(fields, navigator, fn {field, value}, navigator -> update(navigator, field, value) end)
  end

  @doc """

  """
  @spec assign_page(Socket.t, atom, any) :: Socket.t
  @spec assign_page(t, atom, any) :: t
  def assign_page(
    %Socket{private: %{@navigator => %__MODULE__{} = navigator}} = socket,
    key,
    value
  ) when is_atom(key) do
    update_page_assigns(navigator, [{key, value}], [])
    Component.assign(socket, key, value)
  end
  def assign_page(%__MODULE__{} = navigator, key, value) when is_atom(key) do
    update_page_assigns(navigator, [{key, value}], [])
  end
  def assign_page(socket, key, value) do
    Component.assign(socket, key, value)
  end

  @doc """

  """
  @spec assign_page(Socket.t, keyword | map) :: Socket.t
  @spec assign_page(t, keyword | map) :: t
  def assign_page(%Socket{private: %{@navigator => %__MODULE__{} = navigator}} = socket, assigns) do
    update_page_assigns(navigator, assigns, [])
    Component.assign(socket, assigns)
  end
  def assign_page(%__MODULE__{} = navigator, assigns) do
    update_page_assigns(navigator, assigns, [])
  end
  def assign_page(socket, assigns) do
    Component.assign(socket, assigns)
  end

  @doc """

  """
  @spec assign_page_new(Socket.t, atom, assign_new_callback) :: Socket.t
  def assign_page_new(%Socket{private: %{@navigator => %__MODULE__{} = navigator}} = socket, key, setter) do
    wrapper =
      case setter do
        setter when is_function(setter, 0) ->
          fn ->
            value = setter.()
            update_page_assigns(navigator, [{key, value}], [])
            value
          end

        setter when is_function(setter, 1) ->
          fn assigns ->
            value = setter.(assigns)
            update_page_assigns(navigator, [{key, value}], [])
            value
          end
      end
    Component.assign_new(socket, key, wrapper)
  end
  def assign_page_new(%Socket{} = socket, key, setter) do
    Component.assign_new(socket, key, setter)
  end

  @doc """

  """
  @spec clear_page(Socket.t, atom | [atom]) :: Socket.t
  @spec clear_page(t, atom | [atom]) :: t
  def clear_page(%Socket{private: %{@navigator => %__MODULE__{} = navigator}, assigns: assigns} = socket, keys) do
    update_page_assigns(navigator, [], keys)
    %{socket | assigns: clear_assigns(assigns, keys)}
  end
  def clear_page(%__MODULE__{} = navigator, keys) do
    update_page_assigns(navigator, [], keys)
  end
  def clear_page(%Socket{assigns: assigns} = socket, keys) do
    %{socket | assigns: clear_assigns(assigns, keys)}
  end
  def clear_page(socket, _keys) do
    socket
  end

  @doc """

  """
  @spec assign_nav(Socket.t, atom, any) :: Socket.t
  @spec assign_nav(t, atom, any) :: t
  def assign_nav(%Socket{private: %{@navigator => %__MODULE__{} = navigator}} = socket, key, value) when is_atom(key) do
    socket
    |> put_navigator(update_nav_assigns(navigator, [{key, value}], []))
    |> Component.assign(key, value)
  end
  def assign_nav(%__MODULE__{} = navigator, key, value) when is_atom(key) do
    update_nav_assigns(navigator, [{key, value}], [])
  end
  def assign_nav(socket, key, value) do
    Component.assign(socket, key, value)
  end

  @doc """

  """
  @spec assign_nav(Socket.t, keyword | map) :: Socket.t
  @spec assign_nav(t, keyword | map) :: t
  def assign_nav(%Socket{private: %{@navigator => %__MODULE__{} = navigator}} = socket, assigns) do
    socket
    |> put_navigator(update_nav_assigns(navigator, assigns, []))
    |> Component.assign(assigns)
  end
  def assign_nav(%__MODULE__{} = navigator, assigns) do
    update_nav_assigns(navigator, assigns, [])
  end
  def assign_nav(socket, assigns) do
    Component.assign(socket, assigns)
  end

  @doc """

  """
  @spec assign_nav_new(Socket.t, atom, assign_new_callback) :: Socket.t
  def assign_nav_new(
    %Socket{private: %{@navigator => %__MODULE__{} = navigator}} = socket,
    key,
    setter
  ) do
    wrapper =
      case setter do
        setter when is_function(setter, 0) ->
          fn ->
            value = setter.()
            update_nav_assigns(navigator, [{key, value}], [])
            value
          end

        setter when is_function(setter, 1) ->
          fn assigns ->
            value = setter.(assigns)
            update_nav_assigns(navigator, [{key, value}], [])
            value
          end
      end
    socket = Component.assign_new(socket, key, wrapper)
    navigator = Controller.get_navigator()
    put_navigator(socket, navigator)
  end
  def assign_nav_new(%Socket{} = socket, key, setter) do
    Component.assign_new(socket, key, setter)
  end

  @doc """

  """
  @spec clear_nav(Socket.t, atom | [atom]) :: Socket.t
  @spec clear_nav(t, atom | [atom]) :: t
  def clear_nav(%Socket{private: %{@navigator => %__MODULE__{} = navigator}, assigns: assigns} = socket, keys) do
    navigator = update_nav_assigns(navigator, [], keys)
    put_navigator(%{socket | assigns: clear_assigns(assigns, keys)}, navigator)
  end
  def clear_nav(%__MODULE__{} = navigator, keys) do
    update_nav_assigns(navigator, [], keys)
  end
  def clear_nav(%Socket{assigns: assigns} = socket, keys) do
    %{socket | assigns: clear_assigns(assigns, keys)}
  end
  def clear_nav(socket, _keys) do
    socket
  end

  @doc """

  """
  @spec history(Socket.t | t) :: History.t
  def history(%Socket{private: %{@navigator => %__MODULE__{history: history}}}), do: history
  def history(%__MODULE__{history: history}), do: history
  def history(_), do: []

  @doc """

  """
  @spec navigator(Socket.t | t) :: t | nil
  def navigator(%Socket{private: %{@navigator => %__MODULE__{} = navigator}}), do: navigator
  def navigator(%__MODULE__{} = navigator), do: navigator
  def navigator(_), do: nil

  @doc """

  """
  @spec current_url(Socket.t | t) :: binary | nil
  def current_url(%Socket{private: %{@navigator => %__MODULE__{url: url}}}), do: url
  def current_url(%__MODULE__{url: url}), do: url
  def current_url(_), do: nil

  @doc """

  """
  @spec nav_back_url(Socket.t) :: binary | nil
  @spec nav_back_url(Socket.t, History.index) :: binary | nil
  def nav_back_url(socket, index \\ -2)
  def nav_back_url(%Socket{private: %{@navigator => %__MODULE__{view: view, history: history}}}, index) do
    case History.find(history, index) do
      %{url: url} -> url_path(url)
      _ -> get_fallback_url(view)
    end
  end
  def nav_back_url(_socket, _index), do: nil

  @doc """

  """
  @spec nav_pop_stack_url(Socket.t) :: binary | nil
  def nav_pop_stack_url(
    %Socket{private: %{@navigator => %__MODULE__{view: view, history: history}}}
  ) when length(history) < 2 do
    get_fallback_url(view)
  end
  def nav_pop_stack_url(%Socket{private: %{@navigator => %__MODULE__{view: view, history: history}}}) do
    case History.stack_preceding(history) do
      %{url: url} -> url_path(url)
      _ -> get_fallback_url(view)
    end
  end
  def nav_pop_stack_url(_socket), do: nil

  @doc """

  """
  @spec nav_back(Socket.t) :: Socket.t
  @spec nav_back(Socket.t, back_index | keyword) :: Socket.t
  def nav_back(socket, opts \\ [])
  def nav_back(socket, to) when not is_list(to), do: nav_back(socket, to: to)
  def nav_back(%Socket{private: %{@navigator => %__MODULE__{history: history} = navigator}} = socket, opts) do
    {index, unstack} =
      case Keyword.fetch(opts, :to) do
        {:ok, %History{} = spec} -> {spec, false}
        {:ok, {%History{} = spec, unstack}} when is_boolean(unstack) -> {spec, unstack}
        {:ok, {index, unstack}} when (is_integer(index) or is_atom(index)) and is_boolean(unstack) -> {index, unstack}
        {:ok, index} when is_integer(index) or is_atom(index) -> {index, false}
        _ -> {-2, false}
      end
    navigator
    |> navigate_back(History.find(history, index), unstack)
    |> apply_awaiting(socket, opts[:navigate])
  end
  def nav_back(socket, _opts), do: socket

  @spec nav_pop_stack(Socket.t) :: Socket.t
  @spec nav_pop_stack(Socket.t, keyword) :: Socket.t
  def nav_pop_stack(socket, opts \\ [])
  def nav_pop_stack(
    %Socket{private: %{@navigator => %__MODULE__{history: history} = navigator}} = socket,
    opts
  ) when length(history) >= 2 do
    spec = with nil <- History.stack_preceding(history), do: History.find(history, -1)
    navigator
    |> navigate_back(spec, true)
    |> apply_awaiting(socket, opts[:navigate])
  end
  def nav_pop_stack(%Socket{private: %{@navigator => %__MODULE__{view: view} = navigator}} = socket, _opts) do
    url = get_fallback_url(view)
    navigator = update(navigator, :history, [])
    Controller.save(navigator)
    socket
    |> put_navigator(navigator)
    |> LiveView.push_navigate(to: url_path(url))
  end
  def nav_pop_stack(socket, _opts), do: socket

  @spec push_navigate(Socket.t, keyword) :: Socket.t
  def push_navigate(%Socket{private: %{@navigator => %__MODULE__{} = navigator}} = socket, opts) do
    if Keyword.has_key?(opts, :to) do
      navigator
      |> navigate_forward(:navigate, opts)
      |> apply_awaiting(socket, opts[:navigate])
    else
      LiveView.push_navigate(socket, opts)
    end
  end
  def push_navigate(socket, opts), do: LiveView.push_navigate(socket, opts)

  @spec push_patch(Socket.t, keyword) :: Socket.t
  def push_patch(%Socket{private: %{@navigator => %__MODULE__{} = navigator}} = socket, opts) do
    if Keyword.has_key?(opts, :to) do
      navigator
      |> navigate_forward(:patch, opts)
      |> apply_awaiting(socket, opts[:navigate])
    else
      LiveView.push_patch(socket, opts)
    end
  end
  def push_patch(socket, opts), do: LiveView.push_patch(socket, opts)

  @doc deprecated: "Use push_navigate/2 instead"
  # Deprecate in 0.19
  @spec push_redirect(Socket.t, keyword) :: Socket.t
  def push_redirect(%Socket{private: %{@navigator => %__MODULE__{} = navigator}} = socket, opts) do
    if Keyword.has_key?(opts, :to) do
      navigator
      |> navigate_forward(:navigate, opts)
      |> apply_awaiting(socket, opts[:navigate])
    else
      LiveView.push_redirect(socket, opts)
    end
  end
  def push_redirect(socket, opts), do: LiveView.push_redirect(socket, opts)

  @spec redirect(Socket.t, keyword) :: Socket.t
  def redirect(%Socket{private: %{@navigator => %__MODULE__{} = navigator}} = socket, opts) do
    if Keyword.has_key?(opts, :to) do
      navigator
      |> navigate_forward(:redirect, opts)
      |> apply_awaiting(socket, opts[:navigate])
    else
      LiveView.redirect(socket, opts)
    end
  end
  def redirect(socket, opts), do: LiveView.redirect(socket, opts)

  @doc false
  @spec url_path(binary) :: binary
  def url_path(url) do
    to_string(%{URI.parse(url) | scheme: nil, authority: nil, userinfo: nil, host: nil, port: nil})
  end

  @doc false
  @spec now() :: NaiveDateTime.t
  def now, do: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

  defp push_action_spec(navigator, action_method, opts) do
    action =
      cond do
        :stack in opts -> :stack_add
        opts[:stack] == true -> :stack_add
        opts[:stack] == :new -> :stack
        true -> :push
      end
    %{method: action_method}
    |> put_action_spec_as(opts[:as])
    |> put_action_spec_action(action, opts[:replace], navigator)
  end

  @doc false
  defp put_awaiting(%{url: url, view: view, action: action} = navigator, to, action_spec) do
    from = History.new(url, view, action)
    path = URI.parse(to)
    to = URI.to_string(%{URI.parse(url) | path: path.path, query: path.query, fragment: path.fragment})
    navigator
    |> update(:awaiting, {action_spec, to, from})
    |> Controller.save()
  end

  @doc false
  @spec navigate_back(t, History.spec, boolean) :: t
  def navigate_back(%__MODULE__{view: view} = navigator, %{id: id, view: view, url: url}, unstack) do
    put_awaiting(navigator, url, %{method: :patch, action: {:replace, id, unstack}})
  end
  def navigate_back(%__MODULE__{} = navigator, %{id: id, url: url}, unstack) do
    put_awaiting(navigator, url, %{method: :navigate, action: {:replace, id, unstack}})
  end
  def navigate_back(%__MODULE__{view: view} = navigator, _spec, unstack) do
    case get_fallback_url(view) do
      to when is_binary(to) -> put_awaiting(navigator, to, %{method: :navigate, action: {:replace, 0, unstack}})
      _ -> navigator
    end
  end
  def navigate_back(navigator, _spec, _unstack), do: navigator

  @doc false
  @spec navigate_forward(t, action_method, keyword) :: t
  def navigate_forward(%__MODULE__{} = navigator, action, opts) do
    spec = push_action_spec(navigator, action, opts)
    put_awaiting(navigator, opts[:to], spec)
  end
  def navigate_forward(navigator, _action_method, _opts), do: navigator

  @doc false
  @spec clear_assigns(map, atom | [atom]) :: map
  def clear_assigns(assigns, keys) do
    keys = List.wrap(keys)
    changes = Enum.into(keys, %{}, & {&1, true})
    changed = Map.merge(Map.get(assigns, :__changed__, %{}), changes)
    assigns
    |> Map.drop(keys)
    |> Map.put(:__changed__, changed)
  end

  @doc false
  @spec update_page_assigns(t, map | keyword, atom | [atom]) :: t
  def update_page_assigns(navigator, assigns, clear) do
    [%Page{assigns: page_assigns} = page] = load_page(navigator)
    page_assigns =
      page_assigns
      |> Map.merge(Enum.into(assigns, %{}))
      |> Map.drop(List.wrap(clear))
    page
    |> Page.update(:assigns, page_assigns)
    |> Controller.save()
    navigator
  end

  @doc false
  @spec update_nav_assigns(t, map | keyword, atom | [atom]) :: t
  def update_nav_assigns(%{assigns: nav_assigns} = navigator, assigns, clear) do
    nav_assigns =
      nav_assigns
      |> Map.merge(Enum.into(assigns, %{}))
      |> Map.drop(List.wrap(clear))
    navigator
    |> update(:assigns, nav_assigns)
    |> Controller.save()
  end

  @doc false
  @spec get_fallback_url(module) :: url | nil
  def get_fallback_url(view) do
    case view.__navigator__(:fallback_url) do
      nil -> nil
      url when is_binary(url) -> url
      url when is_atom(url) -> if function_exported?(view, url, 0), do: apply(view, url, [])
    end
  end

  defp apply_awaiting(navigator, socket, false), do: put_navigator(socket, navigator)
  defp apply_awaiting(%{awaiting: {%{method: :patch}, to, _}} = navigator, socket, _) do
    socket
    |> put_navigator(navigator)
    |> LiveView.push_patch(to: url_path(to))
  end
  defp apply_awaiting(%{awaiting: {%{method: :navigate}, to, _}} = navigator, socket, _) do
    socket
    |> put_navigator(navigator)
    |> LiveView.push_navigate(to: url_path(to))
  end
  defp apply_awaiting(%{awaiting: {%{method: :redirect}, to, _}} = navigator, socket, _) do
    socket
    |> put_navigator(navigator)
    |> LiveView.redirect(to: url_path(to))
  end

  defp load_page(%__MODULE__{session_id: session_id, tab: tab, view: view, action: action}) do
    Controller.select(Page, session_id: session_id, tab: tab, view: view, action: action)
  end

  defp put_navigator(%Socket{private: private} = socket, navigator) do
    %{socket | private: Map.put(private, @navigator, navigator)}
  end

  defp attach_handle_params(socket) do
    LiveView.attach_hook(socket, :live_navigator_handle_params, :handle_params, &handle_params/3)
  end

  defp attach_handle_info(socket) do
    LiveView.attach_hook(socket, :live_navigator_handle_info, :handle_info, &handle_info/2)
  end

  defp apply_assigns(%Socket{} = socket, %{assigns: assigns}), do: Component.assign(socket, assigns)
  defp apply_assigns(socket, _), do: socket

  # NO NAVIGATOR INITIALIZED YET
  defp checkout_navigator(%{url: nil} = navigator, url, view, action) do
    checkout_new(navigator, url, view, action)
  end
  # REFRESH
  defp checkout_navigator(%{action: action, view: view, url: url, awaiting: nil} = navigator, url, view, action) do
    checkout_refresh(navigator)
  end
  # BACK
  defp checkout_navigator(
    %{
      history: [[_ | [%{url: url, view: view, action: action} = from | _]] | _],
      awaiting: nil,
    } = navigator,
    url,
    view,
    action
  ) do
    checkout_back(navigator, from, url, view, action)
  end
  defp checkout_navigator(
    %{
      history: [prev | [%{url: url, view: view, action: action} = from | _]],
      awaiting: nil,
    } = navigator,
    url,
    view,
    action
  ) when is_map(prev) or length(prev) == 1 do
    checkout_back(navigator, from, url, view, action)
  end
  defp checkout_navigator(
    %{
      history: [prev | [[%{url: url, view: view, action: action} = from | _] | _]],
      awaiting: nil,
    } = navigator,
    url,
    view,
    action
  ) when is_map(prev) or length(prev) == 1 do
    checkout_back(navigator, from, url, view, action)
  end
  # AWAITED ACTION
  defp checkout_navigator(%{history: history, awaiting: {nav_action, url, from}} = navigator, url, view, action) do
    spec = History.new(url, view, action)
    history =
      case nav_action do
        %{action: {:replace, id, unstack}} -> History.replace(history, id, spec, unstack)
        %{action: :stack_add} -> History.put_stacked(history, spec)
        %{action: :stack} -> History.put(history, [spec])
        %{action: :push} -> History.put(history, spec)
      end
    navigator =
      navigator
      |> update(view: view, action: action, url: url, history: history, awaiting: nil)
      |> Controller.save()
    {navigator, [{:leave, nav_action, from}, {:enter, nav_action, from}]}
  end
  # UNEXPECTED ACTION
  defp checkout_navigator(navigator, url, view, action) do
    checkout_new(navigator, url, view, action)
  end

  defp checkout_refresh(navigator) do
    {navigator, [:refresh]}
  end

  defp checkout_back(%{history: history} = navigator, %{id: id} = from, url, view, action) do
    nav_action = %{method: :browse, action: {:replace, id}}
    history = History.replace(history, id, from, false)
    navigator =
      navigator
      |> update(view: view, action: action, url: url, history: history)
      |> Controller.save()
    {navigator, [{:leave, nav_action, from}, {:enter, nav_action, from}]}
  end

  defp checkout_new(%{history: history} = navigator, url, view, action) do
    history = History.put(history, History.new(url, view, action))
    navigator =
      navigator
      |> update(view: view, action: action, url: url, history: history, awaiting: nil)
      |> Controller.save()
    {navigator, [{:enter, %{method: :browse, action: :push}, nil}]}
  end

  defp run_callback(
    :refresh,
    %Socket{private: %{@navigator => %__MODULE__{view: view} = navigator}} = socket
  ) do
    to = History.new(navigator)
    with {:cont, socket} <- Lifecycle.run_lifecycle(view, :on_page_refresh, [to], socket) do
      to
      |> view.handle_page_refresh(socket)
      |> handle_callback_result()
    end
  end
  defp run_callback(
    {:enter, action, from},
    %Socket{private: %{@navigator => %__MODULE__{view: view} = navigator}} = socket
  ) do
    to = History.new(navigator)
    with {:cont, socket} <- Lifecycle.run_lifecycle(view, :on_page_enter, [action, from, to], socket) do
      action
      |> view.handle_page_enter(from, to, socket)
      |> handle_callback_result()
    end
  end
  defp run_callback(
    {:leave, action, %{view: view, action: action} = from},
    %Socket{private: %{@navigator => %__MODULE__{} = navigator}} = socket
  ) do
    to = History.new(navigator)
    navigator = %{navigator | view: view, action: action}
    {cont, navigator} = Lifecycle.run_lifecycle(view, :on_page_leave, [action, from, to], navigator)
    if cont == :cont and function_exported?(view, :handle_page_leave, 4) do
      {:noreply, _navigator} = view.handle_page_leave(action, from, to, navigator)
    end
    {:cont, socket}
  end
  defp run_callback(_, socket), do: {:cont, socket}

  defp handle_callback_result({:noreply, %Socket{redirected: nil} = socket}), do: {:cont, socket}
  defp handle_callback_result({:noreply, socket}), do: {:halt, socket}

  defp put_action_spec_as(spec, nil), do: spec
  defp put_action_spec_as(spec, true), do: spec
  defp put_action_spec_as(spec, false), do: spec
  defp put_action_spec_as(spec, name) when is_atom(name), do: Map.put(spec, :as, name)
  defp put_action_spec_as(spec, _name), do: spec

  defp put_action_spec_action(spec, action, nil, _navigator), do: Map.put(spec, :action, action)
  defp put_action_spec_action(spec, action, true, navigator) do
    put_action_spec_action(spec, action, {-1, false}, navigator)
  end
  defp put_action_spec_action(spec, action, false, _navigator), do: Map.put(spec, :action, action)
  defp put_action_spec_action(spec, action, index, navigator) when is_integer(index) or is_atom(index) do
    put_action_spec_action(spec, action, {index, false}, navigator)
  end
  defp put_action_spec_action(
    spec,
    _action,
    {index, unstack},
    %{history: history}
  ) when (is_integer(index) or is_atom(index)) and is_boolean(unstack) do
    id =
      case History.find(history, index) do
        %{id: id} -> id
        _ -> 0
      end
    Map.put(spec, :action, {:replace, id, unstack})
  end
end
