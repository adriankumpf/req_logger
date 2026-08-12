defmodule ReqLogger.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/adriankumpf/req_logger"

  def project do
    [
      app: :req_logger,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "ReqLogger",
      description: "A Req plugin that logs request method, URL, response status and duration.",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.7"},
      {:plug, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md"],
      maintainers: ["Adrian Kumpf"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", LICENSE: [title: "License"]],
      source_ref: "v#{@version}"
    ]
  end
end
