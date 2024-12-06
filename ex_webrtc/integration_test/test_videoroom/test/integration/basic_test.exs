defmodule TestVideoroom.Integration.BasicTest do
  use TestVideoroomWeb.ConnCase, async: false

  import TestVideoroom.Utils

  alias TestVideoroom.MetricsValidator
  alias TestVideoroom.Browser

  @start_with_all "start-all"
  @start_with_mic "start-mic-only"
  @start_with_camera "start-camera-only"
  @start_with_nothing "start-none"
  @stats "stats"

  @browser_options %{target_url: "http://localhost:4001", receiver: nil, id: -1, headless: true}

  @warmup_time 12_000

  setup do
    browser_options = %{@browser_options | receiver: self()}
    browsers = Enum.map(0..3, &start_browser(browser_options, &1))

    playwrights = Enum.map(browsers, &Browser.get_playwright(&1))

    on_exit(fn ->
      playwrights
      |> Enum.each(fn playwright ->
        Playwright.Browser.close(playwright)
      end)
    end)

    {:ok, %{browsers: browsers}}
  end

  @tag timeout: 120_000
  test "Users gradually joining and leaving can hear and see each other", %{browsers: browsers} do
    browsers_with_id = Enum.zip(browsers, 0..3)

    Enum.each(browsers_with_id, fn {browser, id} ->
      Browser.join(browser, @start_with_all)

      Process.sleep(@warmup_time)

      stats = Browser.get_stats(browser, @stats)
      assert count_playing_streams(stats, "audio") == id
      assert count_playing_streams(stats, "video") == id
    end)

    assertion_function = fn stats_list ->
      Enum.each(stats_list, fn stats ->
        assert count_playing_streams(stats, "audio") == 3
        assert count_playing_streams(stats, "video") == 3
      end)
    end

    assert_stats(browsers, @stats, 10, assertion_function)

    Enum.each(browsers_with_id, fn {browser, id} ->
      stats = Browser.get_stats(browser, @stats)
      assert count_playing_streams(stats, "audio") == 3 - id
      assert count_playing_streams(stats, "video") == 3 - id

      Browser.leave(browser)

      Process.sleep(5_000)
    end)
  end

  @tag timeout: 90_000
  test "Users joining all at once can hear and see each other", %{browsers: browsers} do
    Enum.each(browsers, &Browser.join(&1, @start_with_all))

    Process.sleep(@warmup_time)

    assertion_function = fn stats_list ->
      Enum.each(stats_list, fn stats ->
        assert count_playing_streams(stats, "audio") == 3
        assert count_playing_streams(stats, "video") == 3
      end)
    end

    assert_stats(browsers, @stats, 20, assertion_function)
  end

  @tag timeout: 90_000
  test "Users joining without either microphone, camera or both can see or hear other users", %{
    browsers: browsers
  } do
    browsers_with_start_button =
      Enum.zip(browsers, [
        @start_with_all,
        @start_with_camera,
        @start_with_mic,
        @start_with_nothing
      ])

    browser_received_tracks = [%{a: 1, v: 1}, %{a: 2, v: 1}, %{a: 1, v: 2}, %{a: 2, v: 2}]

    Enum.each(browsers_with_start_button, fn {browser, button} ->
      Browser.join(browser, button)
    end)

    Process.sleep(@warmup_time)

    assertion_function = fn stats_list ->
      stats_with_expected_tracks = Enum.zip(stats_list, browser_received_tracks)

      Enum.each(stats_with_expected_tracks, fn {stats, expected_tracks} ->
        assert count_playing_streams(stats, "audio") == expected_tracks[:a]
        assert count_playing_streams(stats, "video") == expected_tracks[:v]
      end)
    end

    assert_stats(browsers, @stats, 20, assertion_function)
  end

  @tag timeout: 30_000
  test "telemetry events are published", %{browsers: browsers} do
    browsers = Enum.take(browsers, 2)

    assert is_number(Application.fetch_env!(:membrane_rtc_engine_ex_webrtc, :get_stats_interval))
    report_count = 15
    max_invalid_reports = 3

    Enum.each(browsers, &Browser.join(&1, @start_with_all))

    :ok = Process.send(TestVideoroom.MetricsScraper, {:subscribe, self()}, [])

    receive_reports(report_count, max_invalid_reports)
  end

  defp receive_reports(expected_reports, max_invalid_reports, reports \\ [])

  defp receive_reports(0, _max_invalid_reports, reports), do: Enum.reverse(reports)

  defp receive_reports(expected_reports, max_invalid_reports, reports) do
    receive do
      {:metrics, report} ->
        reports = [report | reports]
        valid? = MetricsValidator.validate_report(report) == :ok

        # If one valid report has been received, we expect the next reports to be valid as well
        max_invalid_reports = if valid?, do: 0, else: max_invalid_reports - 1

        if not valid? and max_invalid_reports < 0,
          do: raise("Received too many invalid reports, received reports: #{inspect(reports)}")

        receive_reports(expected_reports - 1, max_invalid_reports, reports)
    after
      2_000 -> raise "Report not received within timeout, received reports: #{inspect(reports)}"
    end
  end
end
