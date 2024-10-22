defmodule TestVideoroom.Integration.BasicTest do
  use TestVideoroomWeb.ConnCase, async: false

  import TestVideoroom.Integration.Utils

  @room_url "http://localhost:4001"

  # in miliseconds
  @warmup_time 6_000

  @start_with_all "start-all"
  @start_with_mic "start-mic-only"
  @start_with_camera "start-camera-only"
  @start_with_nothing "start-none"
  @stats "stats"
  @browser_options %{count: 1, headless: true}
  @actions [
    {:get_stats, @stats, 1, 0, tag: :after_warmup},
    {:wait, 60_000},
    {:get_stats, @stats, 1, 0, tag: :before_leave}
  ]

  @tag timeout: 180_000
  test "Users gradually joining and leaving can hear and see each other" do
    browsers_number = 4

    pid = self()

    receiver = Process.spawn(fn -> receive_stats(browsers_number, pid) end, [:link])

    mustang_options = %{
      target_url: @room_url,
      warmup_time: @warmup_time,
      start_button: @start_with_all,
      actions: @actions,
      receiver: receiver,
      id: -1
    }

    for browser <- 0..(browsers_number - 1), into: [] do
      mustang_options = %{mustang_options | id: browser}

      task =
        Task.async(fn ->
          Stampede.start({TestMustang, mustang_options}, @browser_options)
        end)

      Process.sleep(10_000)
      task
    end
    |> Task.await_many(:infinity)

    receive do
      {:stats, acc} ->
        Enum.each(acc, fn
          {:after_warmup, browsers} ->
            Enum.each(browsers, fn {browser_id, stats_list} ->
              Enum.each(stats_list, fn stats ->
                assert count_playing_streams(stats, "audio") == browser_id
                assert count_playing_streams(stats, "video") == browser_id
              end)
            end)

          {:before_leave, browsers} ->
            Enum.each(browsers, fn {browser_id, stats_list} ->
              Enum.each(stats_list, fn stats ->
                assert count_playing_streams(stats, "audio") == browsers_number - browser_id - 1
                assert count_playing_streams(stats, "video") == browsers_number - browser_id - 1
              end)
            end)
        end)
    end
  end

  @tag timeout: 120_000
  test "Users joining all at once can hear and see each other" do
    browsers_number = 4

    pid = self()

    receiver = Process.spawn(fn -> receive_stats(browsers_number, pid) end, [:link])

    mustang_options = %{
      target_url: @room_url,
      warmup_time: @warmup_time,
      start_button: @start_with_all,
      actions: @actions,
      receiver: receiver,
      id: -1
    }

    for browser <- 0..(browsers_number - 1), into: [] do
      mustang_options = %{mustang_options | id: browser}
      Process.sleep(500)

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

  @tag timeout: 180_000
  test "Users joining without either microphone, camera or both can see or hear other users" do
    browsers_number = 4

    pid = self()

    receiver = Process.spawn(fn -> receive_stats(browsers_number, pid) end, [:link])

    mustang_options = %{
      target_url: @room_url,
      warmup_time: @warmup_time,
      start_button: @start_with_all,
      actions: @actions,
      receiver: receiver,
      id: -1
    }

    buttons_with_id =
      [@start_with_all, @start_with_camera, @start_with_mic, @start_with_nothing]
      |> Enum.with_index()
      |> Map.new(fn {button, browser_id} -> {browser_id, button} end)

    for {browser_id, button} <- buttons_with_id, into: [] do
      specific_mustang = %{mustang_options | start_button: button, id: browser_id}

      Process.sleep(1_000)

      Task.async(fn ->
        Stampede.start({TestMustang, specific_mustang}, @browser_options)
      end)
    end
    |> Task.await_many(:infinity)

    browser_received_tracks = %{
      0 => %{a: 1, v: 1},
      1 => %{a: 2, v: 1},
      2 => %{a: 1, v: 2},
      3 => %{a: 2, v: 2}
    }

    receive do
      {:stats, acc} ->
        Enum.each(acc, fn
          {:after_warmup, browsers} ->
            Enum.each(browsers, fn {browser_id, stats_list} ->
              Enum.each(stats_list, fn stats ->
                assert count_playing_streams(stats, "audio") == browser_received_tracks[browser_id].a
                assert count_playing_streams(stats, "video") == browser_received_tracks[browser_id].v
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
