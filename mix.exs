defmodule Navigator.MixProject do
  use Mix.Project

  def project do
    [
      app: :navigator,
      version: "0.1.0",
      elixir: "~> 1.14",
      source_url: "https://github.com/twips-me/navigator",
      homepage_url: "https://hex.pm/packages/navigator",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
    ]
  end

  def application do
    [
      extra_applications: [:logger],
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 0.18"},
      {:plug, "~> 1.14"},

      # code climate
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.2", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
    ]
  end

  defp docs do
    [
      main: "Navigator",
      extras: ["README.md"],
    ]
  end

  defp description do
    """
    The navigation history and application state for Phoenix LiveView.
    """
  end

  defp package do
    [
      name: "navigator",
      files: ~w[lib .formatter.exs mix.exs README* LICENSE*],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/twips-me/navigator"},
    ]
  end
end
