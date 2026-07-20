defmodule StrFmt do
  @moduledoc """
  A set of macros for formatting strings with ANSI colors, padding, truncation, and screen-width awareness.

  ## Usage

      import StrFmt, except: [to_string: 1]

      iex> strf_sizeb(12000, [:bright]) |> StrFmt.to_string()
      "\e[1m  11.7K\e[0m"

      iex> strf("long msg", [:bright]) |> strf_scr() |> StrFmt.to_string()
      "\e[1mlong msg\e[0m"
  """

  alias IO.ANSI

  @type ansidata :: ANSI.ansidata()

  # Internal representation of a format unit
  # {value, type, options}
  @type unit() ::
          String.t()
          | number()
          | atom()
          | {String.t(), :str, ansidata()}
          | {{integer(), String.t()}, :str, ansidata()}
          | {number(), :sizeb, ansidata()}
          | {integer(), :date, ansidata()}
          | {integer(), :datetime, ansidata()}
          | {String.t(), :scr, ansidata()}
          | {String.t(), {:scr, non_neg_integer()}, ansidata()}
          | {String.t(), :padr, ansidata()}
          | {String.t(), :padl, ansidata()}
          | {{link_text :: String.t(), uri :: String.t()}, :link, ansidata()}
          | [unit()]

  @type t() :: unit() | [unit()]

  # --- Macros ---

  @doc """
  Creates a formatted string unit with optional ANSI styles.
  """
  defmacro strf(msg, opt \\ []) do
    quote do: [{unquote(msg), :str, unquote(opt)}]
  end

  @doc """
  Creates a hyperlink unit.
  """
  defmacro strf_uri_link(uri, link_text, opt \\ []) do
    quote do: [{{unquote(link_text), unquote(uri)}, :link, unquote(opt)}]
  end

  @doc """
  Truncates string to fit remaining screen width (ncols).
  """
  defmacro strf_scr(msg, opt \\ []) do
    quote do: [{unquote(msg), :scr, unquote(opt)}]
  end

  @doc """
  Truncates string to a percentage of the screen width.
  """
  defmacro strf_scr_pcent(msg, pcent, opt \\ []) do
    quote do: [{unquote(msg), {:scr, unquote(pcent)}, unquote(opt)}]
  end

  @doc """
  Formats a Unix timestamp as a date (YYYY-MM-DD).
  """
  defmacro strf_date(timestamp, opt \\ []) do
    quote do: [{unquote(timestamp), :date, unquote(opt)}]
  end

  @doc """
  Formats a Unix timestamp as a datetime (YY-MM-DD HH:MM:SS).
  """
  defmacro strf_datetime(timestamp, opt \\ []) do
    quote do: [{unquote(timestamp), :datetime, unquote(opt)}]
  end

  @doc """
  Pads string to the right using the last character.
  """
  defmacro strf_padr(msg, opt \\ []) do
    quote do: [{unquote(msg), :padr, unquote(opt)}]
  end

  @doc """
  Pads string to the left using the first character.
  """
  defmacro strf_padl(msg, opt \\ []) do
    quote do: [{unquote(msg), :padl, unquote(opt)}]
  end

  @doc """
  Converts bytes to human-readable format (B, K, M, G).
  """
  defmacro strf_sizeb(size, opt \\ []) do
    quote do: [{unquote(size), :sizeb, unquote(opt)}]
  end

  @doc """
  Left-pads a string to a specific width.
  """
  defmacro strf_pad_leading(msg, width, opt \\ []) do
    quote do: [{{unquote(width), unquote(msg)}, :str, unquote(opt)}]
  end

  # --- Public API ---

  @doc """
  Renders the formatted units into a final string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(units) do
    {result, _} = render(units, ncols())
    result
  end

  @doc """
  Prints the rendered string to IO.
  """
  @spec puts(t()) :: :ok
  def puts(units) do
    __MODULE__.to_string(units) |> IO.puts()
  end

  # --- Rendering Engine ---

  @doc false
  def render(units) do
    render(units, ncols())
  end

  @doc false
  def render(units, ncols) do
    List.wrap(units)
    |> List.flatten()
    |> Enum.reduce({"", 0}, fn unit, {acc_str, current_col} ->
      case process_unit(unit, current_col, ncols) do
        {:newline, _len} ->
          # Newline resets column count to 0 for the next item
          {acc_str <> "\n", 0}

        {rendered_str, visual_len} when is_binary(rendered_str) ->
          new_col = current_col + visual_len
          {acc_str <> rendered_str, new_col}
      end
    end)
  end

  # --- Transformation Logic ---

  defp process_unit({date_utc, :datetime, opts}, _acclen, _ncols) when is_integer(date_utc) do
    date_utc
    |> DateTime.from_unix!()
    |> Calendar.strftime("%y-%m-%d %H:%M:%S")
    |> format_and_return(opts)
  end

  defp process_unit({date_utc, :date, opts}, _acclen, _ncols) when is_integer(date_utc) do
    date_utc
    |> DateTime.from_unix!()
    |> DateTime.to_date()
    |> Date.to_string()
    |> format_and_return(opts)
  end

  defp process_unit({{lpad_width, msg}, :str, opts}, _acclen, _ncols) when is_binary(msg) do
    String.pad_leading("#{msg}", lpad_width)
    |> format_and_return(opts)
  end

  defp process_unit({{lpad_width, msg}, :str, _} = unit, acclen, ncols)
       when is_integer(lpad_width) do
    {msg, _msg_sz} = render(msg, ncols)

    put_elem(unit, 0, {lpad_width, msg})
    |> process_unit(acclen, ncols)
  end

  defp process_unit({{msg, visual_len}, :str, opts}, _acclen, _ncols)
       when is_binary(msg) and is_integer(visual_len) do
    format_and_return({msg, visual_len}, opts)
  end

  defp process_unit({msg, :str, opts}, _acclen, _ncols) when is_binary(msg) do
    format_and_return(msg, opts)
  end

  defp process_unit({msg, :str, _opts} = unit, acclen, ncols) do
    {msg, visual_len} = render(msg, ncols)

    put_elem(unit, 0, {msg, visual_len})
    |> process_unit(acclen, ncols)
  end

  defp process_unit({{link_text, uri}, :link, opts}, _acclen, _ncols) do
    format_and_return_link({link_text, uri}, opts)
  end

  defp process_unit({qty, :sizeb, opts}, _acclen, _ncols) when is_number(qty) do
    pretty_size(qty)
    |> format_and_return(opts)
  end

  defp process_unit({msg, :scr, opts}, acclen, ncols) when is_binary(msg) do
    truncate_text(msg, ncols - acclen)
    |> format_and_return(opts)
  end

  defp process_unit({msg, :scr, _} = unit, acclen, ncols) do
    {msg, _msg_sz} = render(msg, ncols)

    put_elem(unit, 0, msg)
    |> process_unit(acclen, ncols)
  end

  defp process_unit({msg, {:scr, pcent}, opts}, acclen, ncols)
       when is_integer(pcent) and pcent <= 100 and pcent >= 0 and is_binary(msg) do
    truncate_text(msg, min(ncols - acclen, div(ncols * pcent, 100)))
    |> format_and_return(opts)
  end

  defp process_unit({msg, {:scr, pcent}, _} = unit, acclen, ncols)
       when is_integer(pcent) and pcent <= 100 and pcent >= 0 do
    {msg, _msg_sz} = render(msg, ncols)

    put_elem(unit, 0, msg)
    |> process_unit(acclen, ncols)
  end

  defp process_unit({msg, :padr, opts}, acclen, ncols) when is_binary(msg) do
    pad_string(&String.last/1, &String.pad_trailing/3, msg, acclen, ncols)
    |> format_and_return(opts)
  end

  defp process_unit({msg, :padr, _} = unit, acclen, ncols) do
    {msg, _msg_sz} = render(msg, ncols)
    put_elem(unit, 0, msg) |> process_unit(acclen, ncols)
  end

  defp process_unit({msg, :padl, opts}, acclen, ncols) when is_binary(msg) do
    pad_string(&String.first/1, &String.pad_leading/3, msg, acclen, ncols)
    |> format_and_return(opts)
  end

  defp process_unit({msg, :padl, _} = unit, acclen, ncols) do
    {msg, _msg_sz} = render(msg, ncols)

    put_elem(unit, 0, msg)
    |> process_unit(acclen, ncols)
  end

  defp process_unit("\n", _col, _ncols), do: {:newline, 0}

  defp process_unit(unit, acclen, ncols)
       when is_number(unit) or is_binary(unit) or is_atom(unit) do
    process_unit({"#{unit}", :str, []}, acclen, ncols)
  end

  defp process_unit({_val, type, _}, acclen, ncols) do
    process_unit(
      {"invalid unit type: `#{inspect(type)}`", :scr, []},
      acclen,
      ncols
    )
  end

  defp format_and_return({str, visual_len}, opts) do
    formatted = ANSI.format(opts ++ [str]) |> IO.chardata_to_string()
    {formatted, visual_len}
  end

  defp format_and_return(str, opts) do
    formatted = ANSI.format(opts ++ [str]) |> IO.chardata_to_string()
    {formatted, :string.length(str)}
  end

  defp format_and_return_link({link_text, uri}, opts) do
    formatted_link = "\e]8;;#{uri}\e\\#{link_text}\e]8;;\e\\"

    formatted = ANSI.format(opts ++ [formatted_link]) |> IO.chardata_to_string()
    {formatted, :string.length(link_text)}
  end

  @doc """
  Pretty print a byte quantity in B, K, M and Gbytes

  Returns a 7 bytes binary (may extends to 8 bytes if qty is negative)
  """
  def pretty_size(qty) when is_integer(qty) do
    abs = abs(qty)

    cond do
      # 10 * 1024 * 1024 * 1024
      abs > 10_737_418_240 ->
        "#{Float.round(qty / 1_073_741_824, 1)}G"

      # 10 * 1024 * 1024
      abs > 10_485_760 ->
        "#{Float.round(qty / 1_048_576, 1)}M"

      # 10 * 1024
      abs > 10_240 ->
        "#{Float.round(qty / 1024, 1)}K"

      true ->
        "#{qty}B"
    end
    |> String.pad_leading(7)
  end

  # --- Helper Functions ---

  def truncate_text(str, max_len) do
    cond do
      max_len <= 0 ->
        ""

      String.length(str) <= max_len ->
        str

      true ->
        mid = max(1, div(max_len, 2) - 1)
        String.slice(str, 0..(mid - 1)) <> ".." <> String.slice(str, -mid..-1)
    end
  end

  defp pad_string(last_char, pad_func, str, acclen, ncols) do
    remaining = ncols - acclen
    last_c = last_char.(str)

    if remaining > 1 and last_c do
      pad_func.(str, remaining, last_c)
    else
      str
    end
  end

  @doc """
  Returns the terminal number of columns.

  Falls back to `40` if unable to detect or in test environment.
  """
  @spec ncols() :: integer()
  if Mix.env() == :test do
    def ncols(), do: 40
  else
    def ncols() do
      case :io.columns() do
        {:ok, ncols} when is_integer(ncols) and ncols > 0 -> ncols
        _ -> 40
      end
    end
  end
end
