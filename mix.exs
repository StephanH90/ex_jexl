defmodule ExJexl.MixProject do
  use Mix.Project

  @version "0.2.1"
  @source_url "https://github.com/stephanh90/ex_jexl"

  def project do
    [
      app: :ex_jexl,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "ExJexl",
      source_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:nimble_parsec, "~> 1.4"},
      {:benchee, "~> 1.0", only: :dev},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "JEXL (JavaScript Expression Language) evaluator for Elixir, built with NimbleParsec."
  end

  defp package do
    [
      name: "ex_jexl",
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["Stephan H"],
      exclude_patterns: ["benchmark/*"]
    ]
  end

  defp docs do
    [
      main: "ExJexl",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      groups_for_modules: [
        Core: [ExJexl],
        Parser: [ExJexl.Parser],
        Evaluator: [ExJexl.Evaluator],
        Transforms: [ExJexl.Transforms]
      ]
    ]
  end
end
