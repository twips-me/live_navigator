defmodule LiveNavigator.JS do
  @moduledoc """
  LiveView JS wrapper necessary to react on `JS.navigate` and `JS.patch`
  """

  alias Phoenix.LiveView.JS

  defdelegate push(event), to: JS
  defdelegate push(event_or_js, opts_or_event), to: JS
  defdelegate push(js, event, opts), to: JS

  defdelegate dispatch(event), to: JS
  defdelegate dispatch(event_or_js, opts_or_event), to: JS
  defdelegate dispatch(js, event, opts), to: JS

  defdelegate toggle(), to: JS
  defdelegate toggle(opts_or_js), to: JS
  defdelegate toggle(js, opts), to: JS

  defdelegate show(), to: JS
  defdelegate show(opts_or_js), to: JS
  defdelegate show(js, opts), to: JS

  defdelegate hide(), to: JS
  defdelegate hide(opts_or_js), to: JS
  defdelegate hide(js, opts), to: JS

  defdelegate add_class(names), to: JS
  defdelegate add_class(names_or_js, opts_or_names), to: JS
  defdelegate add_class(js, names, opts), to: JS

  defdelegate remove_class(names), to: JS
  defdelegate remove_class(names_or_js, opts_or_names), to: JS
  defdelegate remove_class(js, names, opts), to: JS

  defdelegate transition(transition), to: JS
  defdelegate transition(transition_or_js, opts_or_transition), to: JS
  defdelegate transition(js, transition, opts), to: JS

  defdelegate set_attribute(pair), to: JS
  defdelegate set_attribute(pair_or_js, opts_or_pair), to: JS
  defdelegate set_attribute(js, pair, opts), to: JS

  defdelegate remove_attribute(attr), to: JS
  defdelegate remove_attribute(attr_or_js, opts_or_attr), to: JS
  defdelegate remove_attribute(js, attr, opts), to: JS

  defdelegate focus(), to: JS
  defdelegate focus(opts_or_js), to: JS
  defdelegate focus(js, opts), to: JS

  defdelegate focus_first(), to: JS
  defdelegate focus_first(opts_or_js), to: JS
  defdelegate focus_first(js, opts), to: JS

  defdelegate push_focus(), to: JS
  defdelegate push_focus(opts_or_js), to: JS
  defdelegate push_focus(js, opts), to: JS

  defdelegate pop_focus(), to: JS
  defdelegate pop_focus(js), to: JS

  def navigate(href) when is_binary(href) do
    navigate(%JS{}, href, [])
  end
  def navigate(href, opts) when is_binary(href) and is_list(opts) do
    navigate(%JS{}, href, opts)
  end
  def navigate(%JS{} = js, href) when is_binary(href) do
    navigate(js, href, [])
  end
  def navigate(%JS{} = js, href, opts) when is_binary(href) and is_list(opts) do
    {nav_opts, opts} = extract_nav_options(opts, "navigate", href)
    js
    |> JS.push("ln:put-awaiting", value: nav_opts)
    |> JS.navigate(href, opts)
  end

  def patch(href) when is_binary(href) do
    patch(%JS{}, href, [])
  end
  def patch(href, opts) when is_binary(href) and is_list(opts) do
    patch(%JS{}, href, opts)
  end
  def patch(%JS{} = js, href) when is_binary(href) do
    patch(js, href, [])
  end
  def patch(%JS{} = js, href, opts) when is_binary(href) and is_list(opts) do
    {nav_opts, opts} = extract_nav_options(opts, "patch", href)
    js
    |> JS.push("ln:put-awaiting", value: nav_opts)
    |> JS.patch(href, opts)
  end

  def back do
    back(%JS{}, [])
  end
  def back(opts) when is_list(opts) do
    back(%JS{}, opts)
  end
  def back(%JS{} = js) do
    back(js, [])
  end
  def back(%JS{} = js, opts) do
    opts = opts |> Keyword.take(~w[to unstack]a) |> Enum.into(%{})
    JS.push(js, "ln:back", value: opts)
  end

  def pop_stack do
    pop_stack(%JS{})
  end
  def pop_stack(%JS{} = js) do
    JS.push(js, "ln:pop-stack", [])
  end

  defp extract_nav_options(opts, method, href) do
    {nav_opts, opts} = Keyword.split(opts, ~w[replace stack]a)
    nav_opts =
      nav_opts
      |> Enum.into(%{})
      |> Map.put(:method, method)
      |> Map.put(:to, href)
    {nav_opts, opts}
  end
end
