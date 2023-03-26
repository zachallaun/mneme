defmodule LRCPCorrect do
  def parse("/data/" <> rest) do
    with {:ok, session, rest} <- parse_integer(rest),
         {:ok, position, rest} <- parse_integer(rest),
         {:ok, data, ""} <- parse_segment(rest) do
      {:ok, {:data, session: session, position: position, data: data}}
    else
      {:ok, _, rest} -> {:error, rest}
      error -> error
    end
  end

  def parse("/connect/" <> rest) do
    with {:ok, session, ""} <- parse_integer(rest) do
      {:ok, {:connect, session: session}}
    else
      {:ok, _, rest} -> {:error, rest}
      error -> error
    end
  end

  def parse("/ack/" <> rest) do
    with {:ok, session, rest} <- parse_integer(rest),
         {:ok, length, ""} <- parse_integer(rest) do
      {:ok, {:ack, session: session, length: length}}
    else
      {:ok, _, rest} -> {:error, rest}
      error -> error
    end
  end

  def parse("/close/" <> rest) do
    with {:ok, session, ""} <- parse_integer(rest) do
      {:ok, {:close, session: session}}
    else
      {:ok, _, rest} -> {:error, rest}
      error -> error
    end
  end

  def parse(data), do: {:error, data}

  def parse_integer(data) do
    with {:ok, segment, rest} <- parse_segment(data),
         {int, ""} when int >= 0 <- Integer.parse(segment) do
      {:ok, int, rest}
    else
      {int, _} when is_integer(int) -> {:error, data}
      error -> error
    end
  end

  def parse_segment(data, acc \\ <<>>)

  def parse_segment(<<?\\, ?/, rest::binary>>, acc) do
    parse_segment(rest, <<acc::binary, ?/>>)
  end

  def parse_segment(<<?\\, ?\\, rest::binary>>, acc) do
    parse_segment(rest, <<acc::binary, ?\\>>)
  end

  def parse_segment(<<?/, rest::binary>>, acc), do: {:ok, acc, rest}

  def parse_segment(<<char, rest::binary>>, acc) do
    parse_segment(rest, <<acc::binary, char>>)
  end

  def parse_segment(<<>>, acc), do: {:error, acc}
end
