defmodule TestVideoroom.Utils do
  @moduledoc false

  import ExUnit.Assertions

  alias TestVideoroom.Browser

  def start_browser(brower_options, id) do
    {:ok, pid} = Browser.start_link(%{brower_options | id: id})
    pid
  end

  def assert_stats(_browsers, _buttons, 0, _fun), do: :ok

  def assert_stats(browsers, buttons, count, assertion_function) do
    browsers
    |> browsers_with_buttons(buttons)
    |> Enum.each(fn {browser, button} ->
      Browser.fetch_stats_async(browser, button)
    end)

    msgs = Enum.map(0..(length(browsers) - 1), &Browser.receive_stats(&1))

    assertion_function.(msgs)
    assert_stats(browsers, buttons, count - 1, assertion_function)
  end

  def count_playing_streams(streams, kind) do
    streams
    |> Enum.filter(fn
      %{"kind" => ^kind, "playing" => playing} -> playing
      _stream -> false
    end)
    |> Enum.count()
  end

  defp browsers_with_buttons(browsers, buttons) do
    buttons =
      if is_binary(buttons) do
        List.duplicate(buttons, length(browsers))
      else
        assert is_list(buttons)
        assert length(buttons) == length(browsers)
        buttons
      end

    Enum.zip(browsers, buttons)
  end
end
