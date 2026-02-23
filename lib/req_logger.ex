defmodule ReqLogger do
  @moduledoc """
  `Req` Logger plugin.

  Logs the request method, URL and response status with Elixir's Logger.

  ## Options

  - `:log_level` - custom function that receives the `Req.Response` for calculating log level.
    Defaults to `:info` for 2xx responses, `:warning` for 3xx responses and `:error` for 4xx and
    5xxing responses.

  """

  require Logger

  @type log_level_option :: {:log_level, (Req.Response.t() -> Logger.level())}
  @type opts :: [log_level_option()]

  @doc """
  Runs the plugin.

  ## Examples

      iex> req = Req.new() |> ReqLogger.attach()
      iex> Req.get!(req, url: "https://httpbin.org/status/201?a=1")
      # [info] GET https://httpbin.org/status/201 -> 201 (3ms)

  """
  @spec attach(Req.Request.t(), opts()) :: Req.Request.t()
  def attach(request, opts \\ []) do
    request
    |> Req.Request.register_options([:log_level])
    |> Req.Request.merge_options(opts)
    |> Req.Request.append_request_steps(req_logger_wrap_adapter: &wrap_adapter/1)
    |> Req.Request.prepend_response_steps(req_logger_log_message: &log_message/1)
    |> Req.Request.prepend_error_steps(req_logger_log_message: &log_message/1)
  end

  defp wrap_adapter(request) do
    adapter = request.adapter

    wrapped = fn req ->
      start = System.monotonic_time()
      {req, result} = adapter.(req)
      duration = System.monotonic_time() - start
      {Req.Request.put_private(req, :req_logger_duration, duration), result}
    end

    %{request | adapter: wrapped}
  end

  defp log_message({request, response}) do
    level = log_level(response, request.options)
    duration = format_duration(request.private.req_logger_duration)
    Logger.log(level, fn -> format(request, response, duration) end)
    {request, response}
  end

  defp format(request, response, duration) do
    method = request.method |> Atom.to_string() |> String.upcase()
    url = request.url |> Map.put(:query, nil) |> URI.to_string()

    status =
      case response do
        %Req.Response{status: status} -> to_string(status)
        exception when is_exception(exception) -> ["error: ", Exception.message(exception)]
      end

    [method, " ", url, " -> ", status, " (", duration, ")"]
  end

  defp format_duration(duration_native) do
    duration_us = System.convert_time_unit(duration_native, :native, :microsecond)

    cond do
      duration_us < 1_000 -> "#{duration_us}µs"
      duration_us < 1_000_000 -> "#{div(duration_us, 1_000)}ms"
      true -> "#{Float.round(duration_us / 1_000_000, 1)}s"
    end
  end

  defp log_level(exception, _opts) when is_exception(exception), do: :error
  defp log_level(response, %{log_level: fun}) when is_function(fun, 1), do: fun.(response)
  defp log_level(response, _opts), do: default_log_level(response)

  defp default_log_level(%Req.Response{} = res) when res.status >= 400, do: :error
  defp default_log_level(%Req.Response{} = res) when res.status >= 300, do: :warning
  defp default_log_level(%Req.Response{}), do: :info
end
