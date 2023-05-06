# Short demonstration of Mneme's interactive prompts.
# Download and run in your terminal with: elixir tour_mneme.exs

unless Code.ensure_loaded?(Mneme.MixProject) do
  Mix.install([
    {:mneme, ">= 0.0.0"}
  ])
end

## Setup
##

defmodule ExUnitRunner do
  def start do
    {opts, _} = OptionParser.parse!(System.argv(), strict: [only: :keep])

    opts =
      if Keyword.has_key?(opts, :only) do
        filters = ExUnit.Filters.parse(Keyword.get_values(opts, :only))

        opts
        |> Keyword.put(:include, filters)
        |> Keyword.put(:exclude, [:test])
      else
        opts
      end

    ExUnit.start(Keyword.merge([seed: 0], opts))
  end
end

Application.put_env(:mneme, :dry_run, true)
ExUnitRunner.start()
Mneme.start()

## Code to test
##

defmodule HTTPParserNoDuplicateHeaders do
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
  def parse_request(data) do
    with [start_line, rest] <- String.split(data, "\n", parts: 2),
         [method, path, version] <- String.split(start_line),
         {:ok, headers, rest} <- parse_headers(rest) do
      {:ok, [method: method, path: path, version: version, headers: headers], rest}
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
      key = key |> String.trim() |> String.downcase()
      parse_headers(rest, Map.put(headers, key, String.trim(value)))
    else
      _ -> {:error, data}
    end
  end
end

## Tests
##

defmodule HTTPParserTest do
  use ExUnit.Case
  use Mneme

  describe "parse_request/1" do
    alias HTTPParserNoDuplicateHeaders, as: HTTPParser

    @tag example: 1
    test "parses a request with only a start line" do
      auto_assert HTTPParser.parse_request("GET /path HTTP/1.1\n")

      auto_assert HTTPParser.parse_request("MALFORMED\n")
    end

    @tag example: 2
    test "parses a request with headers" do
      auto_assert {:ok,
                   [
                     method: "GET",
                     path: "/path",
                     version: "HTTP/1.1",
                     headers: %{"Accept " => "text/html", "  Host " => "localhost:4000"}
                   ],
                   ""} <-
                    HTTPParser.parse_request("""
                    GET /path HTTP/1.1
                      Host : localhost:4000
                    Accept : text/html
                    """)
    end

    test "parses a request with headers and a body" do
      auto_assert HTTPParser.parse_request("""
                  GET /path HTTP/1.1
                  Host: www.example.org

                  some data
                  """)
    end
  end
end

ExUnit.run()
