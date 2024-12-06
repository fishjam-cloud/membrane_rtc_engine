defmodule TestVideoroom.Integration.BasicTest do
  use TestVideoroomWeb.ConnCase, async: false

  import TestVideoroom.Integration.Utils

  alias TestVideoroom.MetricsValidator

  @room_url "http://localhost:4001"

  # in miliseconds
  @warmup 6_000

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
      warmup_time: @warmup,
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
      warmup_time: @warmup,
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
      warmup_time: @warmup,
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
                assert count_playing_streams(stats, "audio") ==
                         browser_received_tracks[browser_id].a

                assert count_playing_streams(stats, "video") ==
                         browser_received_tracks[browser_id].v
              end)
            end)

          {:before_leave, _browsers} ->
            :ok
        end)
    end
  end

  @tag timeout: 30_000
  test "telemetry events are published" do
    assert is_number(Application.fetch_env!(:membrane_rtc_engine_ex_webrtc, :get_stats_interval))
    browsers_number = 2

    report_count = 15

    pid = self()
    receiver = Process.spawn(fn -> receive_stats(browsers_number, pid) end, [:link])

    :ok = Process.send(TestVideoroom.MetricsScraper, {:subscribe, pid}, [])

    mustang_options = %{
      target_url: @room_url,
      warmup_time: @warmup,
      start_button: @start_with_all,
      actions: [wait: report_count * 1_000],
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

    all_reports = receive_reports()
    valid_reports = Enum.drop_while(all_reports, &(MetricsValidator.validate_report(&1) != :ok))

    results = Enum.map(all_reports, &MetricsValidator.validate_report(&1))
    error_msg = "Too many reports failed. Results: #{inspect(results)}"
    assert length(valid_reports) >= report_count - 3, error_msg

    Enum.each(valid_reports, fn report ->
      assert :ok == MetricsValidator.validate_report(report)
    end)
  end

  defp count_playing_streams(streams, kind) do
    streams
    |> Enum.filter(fn
      %{"kind" => ^kind, "playing" => playing} -> playing
      _stream -> false
    end)
    |> Enum.count()
  end

  defp receive_reports(reports \\ []) do
    receive do
      {:metrics, report} ->
        receive_reports([report | reports])
    after
      0 -> Enum.reverse(reports)
    end
  end
end
