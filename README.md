# StrFmt
[![Test](https://github.com/bougueil/str_fmt/actions/workflows/ci.yml/badge.svg)](https://github.com/bougueil/str_fmt/actions/workflows/ci.yml)
A lightweight Elixir library for formatting strings with ANSI colors, padding, truncation, size conversion, and terminal-width awareness. It provides macros to build formatted output structures that are rendered into final strings only when needed, allowing for dynamic width calculations.

## Installation

Add `str_fmt` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:str_fmt, "~> 0.1.0"}
  ]
end
```

## Usage

Import the module and use the provided macros to construct format units. Finally, convert them to a string using `StrFmt.to_string/1` or print directly with `StrFmt.puts/1`.

```elixir
import StrFmt, except: [to_string: 1]

# Basic String with ANSI styles
iex> strf("Hello World", [:bright]) |> StrFmt.to_string()
"\e[1mHello World\e[0m"

# Human-readable byte sizes
iex> strf_sizeb(12000, [:bright]) |> StrFmt.to_string()
"\e[1m  11.7K\e[0m"

# Screen-aware truncation
# This will truncate the message to fit the remaining terminal width
iex> strf("This is a very long message that might wrap", [:dim]) 
     |> strf_scr() 
     |> StrFmt.to_string()
"\e[2mThis is a ver...\e[0m"

# Combining multiple units
iex> [
...>   strf_date(1672531200, [:bold]),
...>   " - ",
...>   strf("Status: OK", [:green])
...> ] |> StrFmt.to_string()
"\e[1m2023-01-01\e[0m - \e[32mStatus: OK\e[0m"
```

## Features

### ANSI Formatting
All macros accept an optional list of ANSI styles as the second argument. These are passed to `IO.ANSI.format/1`.

```elixir
strf("Error", [:red, :bold])
strf_sizeb(5000, [:cyan])
```

### Screen Width Awareness (`:scr`)
Units marked with `:scr` will be truncated if they exceed the remaining width of the terminal line. This is useful for log messages or table columns.

- `strf_scr(msg)`: Truncates to fit remaining width.
- `strf_scr_pcent(msg, percent)`: Truncates to a percentage of the total terminal width.

### Padding
- `strf_padr(msg)`: Pads the string to the right using its last character.
- `strf_padl(msg)`: Pads the string to the left using its first character.
- `strf_pad_leading(msg, width)`: Left-pads a string to a specific fixed width.

### Data Formatting
- `strf_sizeb(bytes)`: Converts bytes to human-readable format (B, K, M, G). Always returns a 7-character wide string for alignment.
- `strf_date(timestamp)`: Formats a Unix timestamp as `YYYY-MM-DD`.
- `strf_datetime(timestamp)`: Formats a Unix timestamp as `YY-MM-DD HH:MM:SS`.

### Hyperlinks
- `strf_uri_link(uri, text)`: Creates an ANSI hyperlink. Note that the visual length is calculated based on the display text, not the URI.

## API Reference

### Macros

| Macro | Description |
| :--- | :--- |
| `strf(msg, opts)` | Creates a standard string unit with optional styles. |
| `strf_scr(msg, opts)` | Truncates message to fit remaining screen width. |
| `strf_scr_pcent(msg, pct, opts)` | Truncates message to `pct`% of screen width. |
| `strf_date(ts, opts)` | Formats Unix timestamp as date. |
| `strf_datetime(ts, opts)` | Formats Unix timestamp as datetime. |
| `strf_sizeb(size, opts)` | Formats bytes to human-readable string. |
| `strf_padr(msg, opts)` | Pads right using last char. |
| `strf_padl(msg, opts)` | Pads left using first char. |
| `strf_pad_leading(msg, width, opts)` | Left pads to specific width. |
| `strf_uri_link(uri, text, opts)` | Creates a clickable hyperlink unit. |

### Functions

| Function | Description |
| :--- | :--- |
| `to_string(units)` | Renders the list of units into a final string. |
| `puts(units)` | Prints the rendered string to IO. |
| `ncols()` | Returns the detected terminal column count (defaults to 40 in tests). |

## License

MIT License
