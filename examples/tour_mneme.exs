# Short demonstration of Mneme's interactive prompts.
# Download and run in your terminal with: elixir tour_mneme.exs

unless Code.ensure_loaded?(Mneme.MixProject) do
  Mix.install([
    {:mneme, ">= 0.0.0"}
  ])
end

Application.put_env(:mneme, :dry_run, true)
ExUnit.start(seed: 0)
Mneme.start()

defmodule HTTPParserTest do
  use ExUnit.Case
  use Mneme

  describe "request/1" do
    alias HTTPParserNoDuplicateHeaders, as: HTTPParser

    test "parses a request with only a start line" do
      auto_assert HTTPParser.request("GET /path HTTP/1.1\n")

      auto_assert HTTPParser.request("MALFORMED\n")
    end

    test "parses a request with headers" do
      auto_assert HTTPParser.request("""
                  GET /path HTTP/1.1
                  Host: localhost:4000
                  Accept: text/html
                  """)
    end

    test "parses a request with headers and a body" do
      auto_assert HTTPParser.request("""
                  GET /path HTTP/1.1
                  Host: www.example.org

                  some data
                  """)
    end
  end
end

defmodule HTTPParserNoDuplicateHeaders do
  # This module parses an HTTP request but does not handle duplicate headers.

  @doc """
  Returns one of:

      {:ok,
       %{
         method: "METHOD",
         path: "/path",
         version: "HTTP/1.1",
         headers: %{
           "Host" => "..."
         }
       },
       "rest of data"}

  or

      {:error, "where failure occurred"}

  """
  def request(data) do
    with [start_line, rest] <- String.split(data, "\n", parts: 2),
         [method, path, version] <- String.split(start_line),
         {:ok, headers, rest} <- parse_headers(rest) do
      {:ok, %{method: method, path: path, version: version, headers: headers}, rest}
    else
      {:error, _} = error -> error
      _ -> {:error, data}
    end
  end

  defp parse_headers(data, headers \\ %{})

  defp parse_headers("\n" <> rest, headers), do: {:ok, headers, rest}
  defp parse_headers("", headers), do: {:ok, headers, ""}

  defp parse_headers(data, headers) do
    with [header, rest] <- String.split(data, "\n", parts: 2),
         [key, value] <- String.split(header, ":", parts: 2) do
      parse_headers(rest, Map.put(headers, String.trim(key), String.trim(value)))
    else
      _ -> {:error, data}
    end
  end
end

ExUnit.run()
