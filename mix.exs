defmodule Tesla.Middleware.Mold.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/fuelen/tesla_middleware_mold"

  def project do
    [
      app: :tesla_middleware_mold,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Tesla.Middleware.Mold",
      description:
        "Tesla middleware that validates response status codes and parses response bodies via Mold schemas",
      package: package(),
      source_url: @source_url,
      docs: [
        main: "Tesla.Middleware.Mold",
        source_ref: "v#{@version}",
        groups_for_modules: [
          Errors: [
            Tesla.Middleware.Mold.ParseError,
            Tesla.Middleware.Mold.UnexpectedStatusError
          ]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:tesla, "~> 1.8"},
      {:mold, "~> 0.1"},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE.txt)
    ]
  end
end
