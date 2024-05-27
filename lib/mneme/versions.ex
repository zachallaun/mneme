defmodule Mneme.Versions do
  @moduledoc false

  @doc """
  Checks whether the given Elixir or Erlang/OTP versions match the
  system versions.

      Versions.match?(elixir: ">= 1.17.0", otp: ">= 27.0.0")

  """
  def match?(requirements \\ []) do
    requirements = Keyword.validate!(requirements, elixir: ">= 0.0.0", otp: ">= 0.0.0")

    Version.match?(elixir_version(), requirements[:elixir]) and
      Version.match?(otp_version(), requirements[:otp])
  end

  @doc """
  Current Elixir version.
  """
  @spec elixir_version() :: Version.t()
  def elixir_version do
    Version.parse!(System.version())
  end

  @doc """
  Current OTP version.
  """
  @spec otp_version() :: Version.t()
  def otp_version do
    major = System.otp_release()
    version_file = Path.join([:code.root_dir(), "releases", major, "OTP_VERSION"])

    version_file
    |> File.read!()
    |> String.trim()
    |> parse_version!()
  end

  defp parse_version!(version_string) do
    [major, minor, patch] = parse_segments(version_string, 3)
    Version.parse!("#{major}.#{minor}.#{patch}")
  end

  defp parse_segments(s, segment_number)

  defp parse_segments(_, 0) do
    []
  end

  defp parse_segments("." <> rest, segment_number) do
    parse_segments(rest, segment_number)
  end

  defp parse_segments("", segment_number) do
    [0 | parse_segments("", segment_number - 1)]
  end

  defp parse_segments(s, segment_number) do
    case Integer.parse(s) do
      {n, rest} -> [n | parse_segments(rest, segment_number - 1)]
      :error -> [0 | parse_segments("", segment_number - 1)]
    end
  end
end
