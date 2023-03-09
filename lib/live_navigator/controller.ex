defmodule LiveNavigator.Controller do
  @moduledoc false

  alias LiveNavigator.{Page, Storage}

  use GenServer

  @type session_id :: LiveNavigator.session_id
  @type tab :: LiveNavigator.tab
  @type url :: LiveNavigator.url
  @type view :: LiveNavigator.view
  @type action :: LiveNavigator.action

  @app :live_navigator
  @cleanup_timeout Application.compile_env(@app, :cleanup_timeout, 60 * 60) # cleanup every hour
  @nav_ttl Application.compile_env(@app, :nav_ttl, 60 * 60 * 24 * 3) # data TTL is 3 days
  @storage_timeout Application.compile_env(@app, :storage_timeout, :immediately)
  @ack_ttl Application.compile_env(@app, :ack_ttl, 10) # remove stale states after 10 seconds

  @spec start_link() :: GenServer.on_start
  @spec start_link(keyword) :: GenServer.on_start
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_navigator() :: LiveNavigator.t | nil
  @spec get_navigator(pid) :: LiveNavigator.t | nil
  @spec get_navigator(session_id, tab) :: LiveNavigator.t | nil
  def get_navigator(pid \\ self()) do
    case :ets.lookup(LiveNavigator.PIDs, pid) do
      [{_, {session_id, tab}, _}] -> get_navigator(session_id, tab)
      _ -> nil
    end
  end
  def get_navigator(session_id, tab) do
    case :ets.lookup(LiveNavigator, {session_id, tab}) do
      [nav] -> decode(LiveNavigator, nav)
      _ -> nil
    end
  end

  @spec get_page() :: Page.t | nil
  @spec get_page(pid | LiveNavigator.t) :: Page.t | nil
  @spec get_page(session_id, tab, view, action) :: Page.t | nil
  def get_page(pid \\ self())
  def get_page(pid) when is_pid(pid) do
    case :ets.lookup(LiveNavigator.PIDs, pid) do
      [{_pid, {session_id, tab}, {view, action}}] -> get_page(session_id, tab, view, action)
      _ -> nil
    end
  end
  def get_page(%LiveNavigator{session_id: session_id, tab: tab, view: view, action: action}) do
    get_page(session_id, tab, view, action)
  end
  def get_page(session_id, tab, view, action) do
    case :ets.lookup(Page, {session_id, tab, view, action}) do
      [page] -> decode(Page, page)
      _ -> nil
    end
  end

  @spec load_navigator(session_id, tab) :: LiveNavigator.t
  def load_navigator(session_id, tab) do
    now = now()
    pid = self()
    key = {session_id, tab}
    GenServer.cast(__MODULE__, {:monitor, pid})
    case :ets.lookup(LiveNavigator, key) do
      [{_key, ^pid, _, _, _, _, _, _, _} = nav] ->
        :ets.update_element(LiveNavigator, key, [{3, now}])
        GenServer.cast(__MODULE__, {:touch, LiveNavigator, key})
        decode(LiveNavigator, nav)

      [{_key, prev_pid, _, _, _, _, _, _, _} = nav] ->
        :ets.update_element(LiveNavigator, key, [{2, pid}, {3, now}])
        page_key =
          case :ets.lookup(LiveNavigator.PIDs, prev_pid) do
            [{_, _, page_key}] -> page_key
            _ -> nil
          end
        :ets.insert(LiveNavigator.PIDs, {pid, key, page_key})
        :ets.delete(LiveNavigator.PIDs, prev_pid)
        GenServer.cast(__MODULE__, {:ack, key})
        GenServer.cast(__MODULE__, {:touch, LiveNavigator, key})
        decode(LiveNavigator, nav)

      _ ->
        nav = %LiveNavigator{session_id: session_id, tab: tab}
        :ets.insert(LiveNavigator, encode_navigator(nav, pid, now))
        :ets.insert(LiveNavigator.PIDs, {pid, key, nil})
        GenServer.cast(__MODULE__, {:insert, LiveNavigator, key, Map.from_struct(nav)})
        nav
    end
  end

  @spec load_page(session_id, tab, view, action) :: Page.t
  def load_page(session_id, tab, view, action) do
    now = now()
    pid = self()
    key = {session_id, tab, view, action}
    case :ets.lookup(Page, key) do
      [{_key, ^pid, _, _, _} = page] ->
        :ets.update_element(Page, key, [{3, now}])
        GenServer.cast(__MODULE__, {:touch, Page, key})
        decode(Page, page)

      [{_key, prev_pid, _, _, _} = page] ->
        :ets.update_element(Page, key, [{2, pid}, {3, now}])
        :ets.update_element(LiveNavigator.PIDs, prev_pid, [{3, nil}])
        :ets.update_element(LiveNavigator.PIDs, pid, [{3, {view, action}}])
        GenServer.cast(__MODULE__, {:touch, Page, key})
        decode(Page, page)

      _ ->
        page = %Page{session_id: session_id, tab: tab, view: view, action: action}
        :ets.insert(Page, encode_page(page, pid, now))
        :ets.update_element(LiveNavigator.PIDs, pid, [{3, {view, action}}])
        GenServer.cast(__MODULE__, {:insert, Page, key, Map.from_struct(page)})
        page
    end
  end

  @spec save(LiveNavigator.t) :: LiveNavigator.t
  @spec save(Page.t) :: Page.t
  def save(%module{__changed__: [_ | _] = changes} = entity) when module in [LiveNavigator, Page] do
    changes = entity |> Map.from_struct() |> Map.take(changes)
    update = Enum.map(changes, & field(module, &1))
    key = key(entity)
    :ets.update_element(module, key, [{3, now()} | update])
    store_update = Map.merge(changes, Map.take(entity, keys(module)))
    GenServer.cast(__MODULE__, {:update, module, key, store_update})
    %{entity | __changed__: []}
  end
  def save(entity), do: entity

  @spec select(LiveNavigator, keyword) :: [LiveNavigator.t]
  @spec select(Page, keyword) :: [Page.t]
  def select(table, attrs) do
    table
    |> :ets.match_object(match_spec(table, attrs))
    |> Enum.map(& decode(table, &1))
  end

  @impl true
  def init(opts) do
    cleanup_timeout = Keyword.get(opts, :cleanup_timeout, @cleanup_timeout)
    nav_ttl = Keyword.get(opts, :nav_ttl, @nav_ttl)
    storage_timeout = Keyword.get(opts, :storage_timeout, @storage_timeout)
    ack_ttl = Keyword.get(opts, :ack_ttl, @ack_ttl)

    :ets.new(LiveNavigator, [:public, :named_table, read_concurrency: true])
    :ets.new(Page, [:public, :named_table, read_concurrency: true])
    :ets.new(LiveNavigator.PIDs, [:public, :named_table, read_concurrency: true])

    now = now()
    navs = LiveNavigator |> Storage.select() |> Enum.map(& encode_navigator(&1, nil, now))
    :ets.insert(LiveNavigator, navs)
    pages = Page |> Storage.select() |> Enum.map(& encode_page(&1, nil, now))
    :ets.insert(Page, pages)

    st =
      %{
        cleanup_timeout: cleanup_timeout,
        nav_ttl: nav_ttl,
        storage_timeout: storage_timeout,
        ack_ttl: ack_ttl,
        acks: %{},
        updates: %{},
        touches: %{},
      }
      |> restart_cleanup()
      |> restart_storage()
    {:ok, st}
  end

  @impl true
  def handle_info(:cleanup, st) do
    st =
      st
      |> cleanup()
      |> restart_cleanup()
    {:noreply, st}
  end
  def handle_info(:store, %{updates: updates, touches: touches} = st) do
    [LiveNavigator, Page]
    |> Enum.flat_map(fn table ->
      with keys when not is_nil(keys) <- Map.get(touches, table) do
        if MapSet.size(keys) > 0, do: Storage.touch(table, MapSet.to_list(keys))
      end
      updates
      |> Map.get(table, %{})
      |> Enum.map(fn {_key, data} -> struct(table, data) end)
    end)
    |> case do
      [] -> :ok
      updates -> Storage.update(updates)
    end
    {:noreply, restart_storage(st)}
  end
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{ack_ttl: ack_ttl, acks: acks} = st) do
    case :ets.lookup(LiveNavigator.PIDs, pid) do
      [{_, key, _}] ->
        timer = Process.send_after(self(), {:nack, pid, key}, ack_ttl * 1_000)
        {:noreply, %{st | acks: Map.put(acks, key, timer)}}

      _ ->
        {:noreply, st}
    end
  end
  def handle_info({:nack, pid, {session_id, tab} = key}, %{acks: acks} = st) do
    :ets.delete(LiveNavigator.PIDs, pid)
    :ets.delete(LiveNavigator, key)
    :ets.match_delete(Page, {{session_id, tab, :_, :_}, :_, :_, :_})
    Storage.cleanup([{session_id, tab}])
    {:noreply, %{st | acks: Map.delete(acks, key)}}
  end

  @impl true
  def handle_cast({:monitor, pid}, st) do
    Process.monitor(pid)
    {:noreply, st}
  end
  def handle_cast(
    {action, table, _key, data},
    %{storage_timeout: :immediately} = st
  ) when action in ~w[insert update]a do
    Storage.update([struct(table, data)])
    {:noreply, st}
  end
  def handle_cast({:insert, table, key, data}, %{updates: updates} = st) do
    table_updates = Map.get(updates, table, %{})
    updates = Map.put(updates, table, Map.put(table_updates, key, data))
    {:noreply, %{st | updates: updates}}
  end
  def handle_cast({:update, table, key, data}, %{updates: updates} = st) do
    table_updates = Map.get(updates, table, %{})
    update = Map.merge(Map.get(table_updates, key, %{}), data)
    updates = Map.put(updates, table, Map.put(table_updates, key, update))
    {:noreply, %{st | updates: updates}}
  end
  def handle_cast({:ack, key}, %{acks: acks} = st) do
    case Map.pop(acks, key) do
      {nil, _acks} ->
        {:noreply, st}

      {timer, acks} ->
        Process.cancel_timer(timer)
        {:noreply, %{st | acks: acks}}
    end
  end
  def handle_cast({:touch, table, key}, %{touches: touches} = st) do
    touches = Map.put(touches, table, touches |> Map.get(table, MapSet.new()) |> MapSet.put(key))
    {:noreply, %{st | touches: touches}}
  end

  defp field(LiveNavigator, {:url, v}), do: {4, v}
  defp field(LiveNavigator, {:view, v}), do: {5, v}
  defp field(LiveNavigator, {:action, v}), do: {6, v}
  defp field(LiveNavigator, {:awaiting, v}), do: {7, v}
  defp field(LiveNavigator, {:history, v}), do: {8, v}
  defp field(LiveNavigator, {:assigns, v}), do: {9, v}
  defp field(Page, {:assigns, v}), do: {4, v}
  defp field(Page, {:fallback_url, v}), do: {5, v}

  defp key(%LiveNavigator{session_id: session_id, tab: tab}), do: {session_id, tab}
  defp key(%Page{session_id: session_id, tab: tab, view: view, action: action}), do: {session_id, tab, view, action}

  defp keys(LiveNavigator), do: ~w[session_id tab]a
  defp keys(Page), do: ~w[session_id tab view action]a

  defp fields(LiveNavigator), do: ~w[pid ts url view action awaiting history assigns]a
  defp fields(Page), do: ~w[pid ts assigns fallback_url]a

  defp match_spec(table, fields) do
    keys = keys(table)
    {key, fields} = Keyword.split(fields, keys)
    key = keys |> Enum.map(& Keyword.get(key, &1, :_)) |> List.to_tuple()
    fields = table |> fields() |> Enum.map(& Keyword.get(fields, &1, :_))
    List.to_tuple([key | fields])
  end

  defp decode(LiveNavigator, {{session_id, tab}, _pid, _ts, url, view, action, awaiting, history, assigns}) do
    %LiveNavigator{
      session_id: session_id,
      tab: tab,
      url: url,
      view: view,
      action: action,
      awaiting: awaiting,
      history: history,
      assigns: assigns,
    }
  end
  defp decode(Page, {{session_id, tab, view, action}, _pid, _ts, assigns, fallback_url}) do
    %Page{
      session_id: session_id,
      tab: tab,
      view: view,
      action: action,
      assigns: assigns,
      fallback_url: fallback_url,
    }
  end

  defp encode_navigator(
    %LiveNavigator{
      session_id: session_id,
      tab: tab,
      url: url,
      view: view,
      action: action,
      awaiting: awaiting,
      history: history,
      assigns: assigns,
    },
    pid,
    ts
  ) do
    {{session_id, tab}, pid, ts, url, view, action, awaiting, history, assigns}
  end

  defp encode_page(
    %Page{
      session_id: session_id,
      tab: tab,
      view: view,
      action: action,
      assigns: assigns,
      fallback_url: fallback_url
    },
    pid,
    ts
  ) do
    {{session_id, tab, view, action}, pid, ts, assigns, fallback_url}
  end

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.to_gregorian_seconds() |> elem(0)

  defp cleanup(%{nav_ttl: ttl} = st) do
    ts = now() - ttl
    spec = [{{:"$1", :"$2", :_, :_, :_, :_, :_, :_, :_}, [{:<, :"$2", ts}], [:"$1"]}]
    to_delete = :ets.select(LiveNavigator, spec)
    Enum.each(to_delete, fn {session_id, tab} ->
      :ets.match_delete(Page, {{session_id, tab, :_, :_}, :_, :_, :_})
    end)
    Storage.cleanup(to_delete)
    st
  end

  defp restart_cleanup(%{cleanup_timeout: period} = st) do
    Process.send_after(self(), :cleanup, period * 1_000)
    st
  end

  defp restart_storage(%{storage_timeout: :immediately} = st), do: st
  defp restart_storage(%{storage_timeout: period} = st) do
    Process.send_after(self(), :store, period * 1_000)
    st
  end
end
