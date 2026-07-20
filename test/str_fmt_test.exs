defmodule StrFmtTest do
  use ExUnit.Case, async: true

  import StrFmt, except: [to_string: 1]

  # Helper to strip ANSI codes for easier assertion of text content
  defp strip_ansi(str) do
    str |> String.replace(~r/\e\[[0-9;]*m/, "") |> String.replace(~r/\e\[K/, "")
  end

  setup do
    # Ensure we are in a consistent state regarding terminal width detection
    # The module definition handles Mix.env() == :test by returning 40
    on_exit(fn -> nil end)
  end

  describe "strf/2 (Basic String)" do
    test "renders plain string" do
      assert StrFmt.to_string(strf("Hello")) == "Hello"
    end

    test "applies ANSI styles" do
      result = strf("Error", [:red, :bold]) |> StrFmt.to_string()
      # bold
      assert String.contains?(result, "\e[1m")
      # red
      assert String.contains?(result, "\e[31m")
      assert strip_ansi(result) == "Error"
    end

    test "handles empty string" do
      assert StrFmt.to_string(strf("")) == ""
    end
  end

  describe "strf_sizeb/2 (Byte Formatting)" do
    test "formats bytes correctly" do
      assert strip_ansi(StrFmt.to_string(strf_sizeb(100))) == "   100B"
      assert strip_ansi(StrFmt.to_string(strf_sizeb(1024))) == "  1024B"
      assert strip_ansi(StrFmt.to_string(strf_sizeb(1_048_576))) == "1024.0K"
      assert strip_ansi(StrFmt.to_string(strf_sizeb(1_073_741_824))) == "1024.0M"
    end

    test "formats negative bytes" do
      # Note: pretty_size handles abs, but keeps sign in float division? 
      # Looking at code: Float.round(qty / ..., 1). If qty is negative, result is negative.
      assert strip_ansi(StrFmt.to_string(strf_sizeb(-1024))) == " -1024B"
    end

    test "pads to 7 characters" do
      # 100B -> "   100B" (length 6? No, pad_leading(7))
      # Let's check the pretty_size logic: String.pad_leading(7)
      # "100B" is 4 chars. Pad to 7 -> "   100B"
      result = strf_sizeb(100) |> StrFmt.to_string() |> strip_ansi()
      assert String.length(result) == 7
    end
  end

  describe "strf_date/2 and strf_datetime/2" do
    test "formats date correctly" do
      # Jan 1, 2023 00:00:00 UTC
      timestamp = 1_672_531_200

      date_result = strf_date(timestamp) |> StrFmt.to_string() |> strip_ansi()
      assert date_result == "2023-01-01"

      datetime_result = strf_datetime(timestamp) |> StrFmt.to_string() |> strip_ansi()
      # Format: YY-MM-DD HH:MM:SS
      assert datetime_result == "23-01-01 00:00:00"
    end
  end

  describe "strf_scr/2 (Screen Truncation)" do
    test "truncates if message exceeds remaining width" do
      # Terminal width is 40 in tests.
      # Current col starts at 0.
      # Message length 50. Should truncate.
      long_msg = String.duplicate("a", 50)

      result = strf_scr(long_msg) |> StrFmt.to_string() |> strip_ansi()

      # Truncation logic: mid = div(40, 2) - 1 = 19.
      # Slice 0..18 (19 chars) <> ".." <> Slice -19..-1 (19 chars)
      # Total length: 19 + 2 + 19 = 40.
      assert String.length(result) == 40
      assert String.contains?(result, "..")
    end

    test "does not truncate if message fits" do
      short_msg = "Short"
      result = strf_scr(short_msg) |> StrFmt.to_string() |> strip_ansi()
      assert result == "Short"
    end

    test "handles empty remaining width" do
      # Simulate being at the end of the line by adding a long prefix
      # Note: The render engine tracks `current_col`.
      # If we put a 40-char string first, current_col is 40.
      # Next item has acclen=40, ncols=40. Remaining = 0.

      prefix = String.duplicate("x", 40)
      suffix = "Should be gone"

      result = [strf(prefix), strf_scr(suffix)] |> StrFmt.to_string() |> strip_ansi()

      # The suffix should be truncated to "" because max_len <= 0
      assert result == prefix
    end
  end

  describe "strf_scr_pcent/3 (Percentage Truncation)" do
    test "truncates based on percentage of total width" do
      # Total width 40. 50% is 20 chars.
      long_msg = String.duplicate("a", 100)

      result = strf_scr_pcent(long_msg, 50) |> StrFmt.to_string() |> strip_ansi()

      # Logic: min(ncols - acclen (40), div(40 * 50, 100) (20)) -> max_len = 20.
      # mid = div(20, 2) - 1 = 9.
      # Slice 0..8 (9 chars) <> ".." <> Slice -9..-1 (9 chars)
      # Total: 9 + 2 + 9 = 20.
      assert String.length(result) == 20
    end
  end

  describe "Padding Macros" do
    test "strf_padr pads right with last char" do
      # Width 40. Col 0. Msg "Hi". Last char 'i'.
      # Remaining 40. Pad trailing to 40 with 'i'.
      result = strf_padr("Hi") |> StrFmt.to_string() |> strip_ansi()
      assert String.length(result) == 40
      assert String.starts_with?(result, "Hi")
      assert String.ends_with?(result, "iiii")
    end

    test "strf_padl pads left with first char" do
      result = strf_padl("Hi") |> StrFmt.to_string() |> strip_ansi()
      assert String.length(result) == 40
      assert String.starts_with?(result, "HHHH")
      assert String.ends_with?(result, "Hi")
    end

    test "strf_pad_leading pads to specific width" do
      # Width 10. Msg "Hi".
      result = strf_pad_leading("Hi", 10) |> StrFmt.to_string() |> strip_ansi()
      assert result == "        Hi"
      assert String.length(result) == 10
    end
  end

  describe "strf_uri_link/3 (Hyperlinks)" do
    test "creates hyperlink structure" do
      result = strf_uri_link("http://example.com", "Click Me") |> StrFmt.to_string()

      # ANSI Hyperlink format: \e]8;;URI\e\\Text\e]8;;\e\\
      assert String.contains?(result, "\e]8;;http://example.com\e\\Click Me\e]8;;\e\\")
    end

    test "calculates visual length based on text only" do
      # The render engine should return the length of "Click Me" (8), not the URI.
      # We can verify this by checking if subsequent items are positioned correctly.
      prefix = "Start:"
      link = strf_uri_link("http://very-long-uri-that-should-not-affect-width.com", "Link")
      suffix = "End"

      result = [strf(prefix), link, strf(suffix)] |> StrFmt.to_string() |> strip_ansi()

      assert result == "Start:\e]8;;http://very-long-uri-that-should-not-affect-width.com\e\\Link\e]8;;\e\\End"
    end
  end

  describe "Newlines and Mixed Units" do
    test "handles newlines resetting column count" do
      line1 = String.duplicate("a", 40)
      line2 = "Short"

      result = [strf(line1), "\n", strf(line2)] |> StrFmt.to_string() |> strip_ansi()

      assert result == "#{line1}\n#{line2}"
    end

    test "handles mixed types (atoms, numbers)" do
      result =
        [:ok, 42, "String"]
        |> Enum.map(fn x ->
          case x do
            a when is_atom(a) -> strf(to_string(a))
            n when is_number(n) -> strf(to_string(n))
            s -> strf(s)
          end
        end)
        |> List.flatten()
        |> StrFmt.to_string()
        |> strip_ansi()

      assert result == "ok42String"
    end
  end

  describe "Edge Cases" do
    test "empty list returns empty string" do
      assert StrFmt.to_string([]) == ""
    end

    test "nested lists are flattened" do
      result = [[strf("A"), strf("B")], strf("C")] |> StrFmt.to_string() |> strip_ansi()
      assert result == "ABC"
    end
  end
end
