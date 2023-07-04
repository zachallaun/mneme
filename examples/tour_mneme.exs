# Short demonstration of Mneme's interactive prompts.
# Download and run in your terminal with: elixir tour_mneme.exs

unless Version.match?(System.version(), "~> 1.14") do
  raise RuntimeError, "Mneme requires Elixir ~> 1.14 (current: #{System.version()})"
end

unless Code.ensure_loaded?(Mneme.MixProject) do
  Mix.install([
    {:mneme, ">= 0.0.0"}
  ])
end

## Setup
##

ExUnit.start(seed: 0)
Mneme.start(dry_run: true)

defmodule Tour do
  @prefix [Owl.Data.tag(" Tour ", [:magenta_background, :bright]), " "]
  @continue [Owl.Data.tag("      ", :magenta_background), " "]

  def await(message, prompt \\ "continue") do
    [message, "\n\n", Owl.Data.tag("#{prompt} ⏎ ", :faint)]
    |> puts()

    _ = IO.gets("")

    IO.puts(IO.ANSI.cursor_up(2))

    :ok
  end

  def puts(message) do
    [first | rest] = Owl.Data.lines(message)

    data =
      [[], [@prefix, first] | Enum.map(rest, &[@continue, &1])]
      |> Owl.Data.unlines()

    [data, "\n\n"]
    |> Owl.Data.to_ansidata()
    |> IO.write()
  end
end

## Code
##

defmodule HTTPParser do
  def parse_request!(data, header_opt \\ :list) do
    case parse_request(data, header_opt) do
      {:ok, request} -> request
      {:error, _} -> raise ArgumentError, "invalid HTTP request"
    end
  end

  def parse_request(data, header_opt \\ :basic) do
    with [start_line, rest] <- String.split(data, "\n", parts: 2),
         [method, path, version] <- String.split(start_line),
         {:ok, headers, body} <- parse_headers(header_opt, rest, %{}) do
      {:ok, [method: method, path: path, version: version, headers: headers, body: body]}
    else
      {:error, _} = error -> error
      _ -> {:error, data}
    end
  end

  defp parse_headers(_, "\n" <> rest, headers), do: {:ok, headers, rest}
  defp parse_headers(_, "", headers), do: {:ok, headers, ""}

  defp parse_headers(:basic, data, headers) do
    with {:ok, {key, value}, rest} <- next_header(data) do
      parse_headers(:basic, rest, Map.put(headers, key, value))
    end
  end

  defp parse_headers(:normalize, data, headers) do
    with {:ok, {key, value}, rest} <- next_header(data) do
      key = key |> String.trim() |> String.downcase()
      parse_headers(:normalize, rest, Map.put(headers, key, value))
    end
  end

  defp parse_headers(:list, data, headers) do
    with {:ok, {key, value}, rest} <- next_header(data) do
      key = key |> String.trim() |> String.downcase()
      parse_headers(:list, rest, Map.update(headers, key, [value], &[value | &1]))
    end
  end

  defp next_header(data) do
    with [header, rest] <- String.split(data, "\n", parts: 2),
         [key, value] <- String.split(header, ":", parts: 2) do
      {:ok, {key, String.trim(value)}, rest}
    else
      _ -> {:error, data}
    end
  end
end

defmodule HTTPParserNormalizeKeys do
  def parse_request(data), do: HTTPParser.parse_request(data, :normalize)
end

defmodule HTTPParserListValues do
  def parse_request(data), do: HTTPParser.parse_request(data, :list)
end

## Tests
##

defmodule HTTPParserTest do
  use ExUnit.Case
  use Mneme

  describe "parse_request/1" do
    @tag example: 1
    test "parses a request with only a start line" do
      import HTTPParser

      Tour.await([
        "Welcome to the ",
        Owl.Data.tag("Mneme Tour", [:bright, :magenta]),
        "! We're going to run through some tests using\nMneme's auto-assertions.\n\n",
        """
        We're going to be testing a basic HTTP request parser. Here's how it
        might be called:

            parse_request("GET /path HTTP/1.1\\n")

        Let's see what happens when we \
        """,
        Owl.Data.tag("auto_assert", :magenta),
        " that expression."
      ])

      auto_assert parse_request("GET /path HTTP/1.1\n")
    end

    test "returns an error for a malformed request" do
      import HTTPParser

      Tour.await([
        "When Mneme encounters an ",
        Owl.Data.tag("auto_assert", :magenta),
        " without an existing pattern,\n",
        "you're prompted with a pattern that you can ",
        [Owl.Data.tag("accept", :green), ", "],
        [Owl.Data.tag("reject", :red), ", or "],
        [Owl.Data.tag("skip", :yellow), "."],
        "\n\nLet's look at another assertion, this time for a malformed request."
      ])

      auto_assert parse_request("MALFORMED\n")
    end

    test "parses a request with headers" do
      import HTTPParserNormalizeKeys

      Tour.await("""
      Now let's see what happens when things change and the existing pattern
      doesn't match. Pretend we've just updated our parser to normalize the
      keys in headers.\
      """)

      auto_assert {:ok,
                   [
                     method: "GET",
                     path: "/path",
                     version: "HTTP/1.1",
                     headers: %{"Accept " => "text/html", "Host " => "localhost:4000"},
                     body: ""
                   ]} <-
                    parse_request("""
                    GET /path HTTP/1.1
                    Host : localhost:4000
                    Accept : text/html
                    """)
    end

    test "parses a request with duplicate headers" do
      import HTTPParserListValues

      Tour.await("""
      HTTP headers can also be duplicated, so let's look at another example
      that supposes we've updated our parser to handle that.\
      """)

      auto_assert {:ok,
                   [
                     method: "GET",
                     path: "/path",
                     version: "HTTP/1.1",
                     headers: %{"accept" => "application/json", "host" => "localhost:4000"},
                     body: ""
                   ]} <-
                    parse_request("""
                    GET /path HTTP/1.1
                    Host: localhost:4000
                    Accept: text/html
                    Accept: application/json
                    """)
    end
  end

  describe "parse_request!/1" do
    test "raises on a malformed request" do
      import HTTPParser

      Tour.await([
        "While these examples have all used ",
        Owl.Data.tag("auto_assert", :magenta),
        ", there are a few other\n",
        "auto-assertions available as well.\n\n",
        "Let's look at ",
        Owl.Data.tag("auto_assert_raise", :magenta),
        ", which we'll use to test a version of\n",
        "our parse function that raises on error.\n\n",
        "Tip: try using ",
        [Owl.Data.tag("j", :bright), " and ", Owl.Data.tag("k", :bright)],
        " to cycle through the two options."
      ])

      auto_assert_raise parse_request!("MALFORMED")
    end

    test "fin" do
      Tour.await("""
      After acting on any auto-assertions, the ExUnit test runner will report
      results as usual. You'll see them when you continue.

      If you accepted everything above, all of the tests should pass.\
      """)
    end
  end
end

ExUnit.run()

Tour.puts("""
That's all we have!

This tour was run in a "dry-run" mode, so you can re-run it as many
times as you'd like.\
""")
