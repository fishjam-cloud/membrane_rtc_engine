defmodule TestVideoroom.Integration.NoVideoTest do
  alias Membrane.RTC.Engine.Endpoint
  use TestVideoroomWeb.ConnCase, async: false

  import TestVideoroom.Utils

  alias TestVideoroom.Browser

  @start_with_all "start-all"
  @start_with_mic "start-mic-only"
  @start_with_camera "start-camera-only"
  @start_with_nothing "start-none"
  @disable_video "video-off"
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
  test "Users gradually joining and leaving can hear but not see each other", %{browsers: browsers} do
    browsers_with_id = Enum.zip(browsers, 0..3)
    
    Enum.each(browsers, &Browser.click(&1, @disable_video))

    Enum.each(browsers_with_id, fn {browser, id} ->
      Browser.join(browser, @start_with_all)

      Process.sleep(@warmup_time)

      stats = Browser.get_stats(browser, @stats)
      assert count_playing_streams(stats, "audio") == id
      assert count_playing_streams(stats, "video") == 0
    end)

    assertion_function = fn stats_list ->
      Enum.each(stats_list, fn stats ->
        assert count_playing_streams(stats, "audio") == 3
        assert count_playing_streams(stats, "video") == 0
      end)
    end

    assert_stats(browsers, @stats, 10, assertion_function)

    Enum.each(browsers_with_id, fn {browser, id} ->
      stats = Browser.get_stats(browser, @stats)
      assert count_playing_streams(stats, "audio") == 3 - id
      assert count_playing_streams(stats, "video") == 0

      Browser.leave(browser)

      Process.sleep(5_000)
    end)
  end

  @tag timeout: 90_000
  test "Users joining all at once can hear but not see each other", %{browsers: browsers} do
    Enum.each(browsers, &Browser.click(&1, @disable_video))
    Enum.each(browsers, &Browser.join(&1, @start_with_all))

    Process.sleep(@warmup_time)

    assertion_function = fn stats_list ->
      Enum.each(stats_list, fn stats ->
        assert count_playing_streams(stats, "audio") == 3
        assert count_playing_streams(stats, "video") == 0
      end)
    end

    assert_stats(browsers, @stats, 20, assertion_function)
  end
end
