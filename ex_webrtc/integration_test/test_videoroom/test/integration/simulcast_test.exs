defmodule TestVideoroom.Integration.SimulcastTest do
  use TestVideoroomWeb.ConnCase, async: false

  import TestVideoroom.Integration.Utils

  @room_url "http://localhost:4001"

  # in miliseconds
  @warmup_time 10_000

  @start_with_simulcast "start-simulcast"

  @browser_options %{count: 1, headless: true}
  @max_test_duration 240_000

  @tag timeout: @max_test_duration
  test "Participants receive audio and video when using simulcast" do
    browsers_number = 2

    pid = self()

    receiver = Process.spawn(fn -> receive_stats(browsers_number, pid) end, [:link])

    actions = [
      {:get_stats, "stats", 1, 0, tag: :after_warmup},
      {:wait, 60_000},
      {:get_stats, "stats", 1, 0, tag: :before_leave}
    ]

    mustang_options = %{
      target_url: @room_url,
      warmup_time: @warmup_time,
      start_button: @start_with_simulcast,
      actions: actions,
      receiver: receiver,
      id: -1
    }

    for browser <- 0..(browsers_number - 1), into: [] do
      mustang_options = %{mustang_options | id: browser}

      Task.async(fn ->
        Stampede.start({TestMustang, mustang_options}, @browser_options)
      end)
    end
    |> Task.await_many(:infinity)

    receive do
      {:stats, acc} ->
        Enum.each(acc, fn
          {:after_warmup, browsers} ->
            Enum.each(browsers, fn {_browser_id, stats_list} ->
              Enum.each(stats_list, fn stats ->
                assert count_playing_streams(stats, "audio") == browsers_number - 1
                assert count_playing_streams(stats, "video") == browsers_number - 1
              end)
            end)

          {:before_leave, _browsers} ->
            :ok
        end)
    end
  end

  defp count_playing_streams(streams, kind) do
    streams
    |> Enum.filter(fn
      %{"kind" => ^kind, "playing" => playing} -> playing
      _stream -> false
    end)
    |> Enum.count()
  end
end
