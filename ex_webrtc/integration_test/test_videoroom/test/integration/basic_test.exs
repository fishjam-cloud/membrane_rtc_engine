defmodule TestVideoroom.Integration.BasicTest do
  use TestVideoroomWeb.ConnCase, async: false

  import TestVideoroom.Integration.Utils

  @room_url "http://localhost:4001"

  # in miliseconds
  @short_warmup 15_000
  @long_warmup 25_000

  @start_with_all "start-all"
  @start_with_mic "start-mic-only"
  @start_with_camera "start-camera-only"
  @start_with_nothing "start-none"
  @stats "stats"
  @browser_options %{count: 1, headless: true}
  @actions [
    {:get_stats, @stats, 1, 0, tag: :after_warmup},
    {:wait, 90_000},
    {:get_stats, @stats, 1, 0, tag: :before_leave}
  ]

  @tag timeout: 240_000
  test "Users gradually joining and leaving can hear and see each other" do
    browsers_number = 4

    pid = self()

    receiver = Process.spawn(fn -> receive_stats(browsers_number, pid) end, [:link])

    mustang_options = %{
      target_url: @room_url,
      warmup_time: @short_warmup,
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

      Process.sleep(20_000)
      task
    end
    |> Task.await_many(:infinity)

    receive do
      {:stats, acc} ->
        Enum.each(acc, fn
          {:after_warmup, browsers} ->
            Enum.each(browsers, fn {browser_id, stats_list} ->
              Enum.each(stats_list, fn stats ->
                assert length(stats) == 2 * browser_id
                assert Enum.all?(stats, &is_stream_playing(&1))
              end)
            end)

          {:before_leave, browsers} ->
            Enum.each(browsers, fn {browser_id, stats_list} ->
              Enum.each(stats_list, fn stats ->
                assert length(stats) == 2 * (browsers_number - browser_id - 1)
                assert Enum.all?(stats, &is_stream_playing(&1))
              end)
            end)
        end)
    end
  end

  @tag timeout: 180_000
  test "Users joining all at once can hear and see each other" do
    browsers_number = 4

    pid = self()

    receiver = Process.spawn(fn -> receive_stats(browsers_number, pid) end, [:link])

    mustang_options = %{
      target_url: @room_url,
      warmup_time: @long_warmup,
      start_button: @start_with_all,
      actions: @actions,
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
                assert length(stats) == 2 * (browsers_number - 1)
                assert Enum.all?(stats, &is_stream_playing(&1))
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
      warmup_time: @short_warmup,
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

    browser_received_tracks = %{0 => 2, 1 => 3, 2 => 3, 3 => 4}

    receive do
      {:stats, acc} ->
        Enum.each(acc, fn
          {:after_warmup, browsers} ->
            Enum.each(browsers, fn {browser_id, stats_list} ->
              Enum.each(stats_list, fn stats ->
                assert length(stats) == browser_received_tracks[browser_id]
                assert Enum.all?(stats, &is_stream_playing(&1))
              end)
            end)

          {:before_leave, _browsers} ->
            :ok
        end)
    end
  end

  defp is_stream_playing(%{"streamId" => _, "playing" => playing, "kind" => _kind}) do
    playing == true
  end
end