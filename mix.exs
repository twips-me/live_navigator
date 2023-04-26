defmodule LiveNavigator.MixProject do
  use Mix.Project

  def project do
    [
      app: :live_navigator,
      version: "0.1.8",
      elixir: "~> 1.14",
      source_url: "https://github.com/twips-me/live_navigator",
      homepage_url: "https://hex.pm/packages/live_navigator",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      aliases: aliases(Mix.env),
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
      {:esbuild, "~> 0.5", runtime: false},

      # code climate
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.2", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
    ]
  end

  defp docs do
    [
      main: "LiveNavigator",
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
      name: "live_navigator",
      files: ~w[lib dist .formatter.exs mix.exs package.json README* LICENSE*],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/twips-me/live_navigator"},
    ]
  end

  defp aliases(:prod) do
    [
      "assets.build": [
        "cmd rm -rf assets/node_modules",
        "cmd --cd assets npm install --quite",
        "esbuild --runtime-config default assets/js/live_navigator.js --minify --format=esm --outdir=dist",
      ],
    ]
  end
  defp aliases(_) do
    [
      "assets.build": [
        "cmd rm -rf assets/node_modules",
        "cmd --cd assets npm install --quite",
        "esbuild --runtime-config default assets/js/live_navigator.js --format=esm --outdir=dist",
      ],
    ]
  end
end
