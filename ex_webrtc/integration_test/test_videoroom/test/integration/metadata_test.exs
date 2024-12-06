defmodule TestVideoroom.Integration.MetadataTest do
  use TestVideoroomWeb.ConnCase, async: false

  import TestVideoroom.Utils

  alias TestVideoroom.Browser

  @start_all "start-all"
  @start_all_update "start-all-update"
  @update_peer "metadata-update-peer"
  @update_track "metadata-update-track"
  @metadata_peer "metadata-peer"
  @metadata_track "metadata-track"

  @browser_options %{target_url: "http://localhost:4001", receiver: nil, id: -1, headless: true}

  @warmup_time 8_000

  setup do
    browser_options = %{@browser_options | receiver: self()}
    browsers = Enum.map(0..1, &start_browser(browser_options, &1))

    playwrights = Enum.map(browsers, &Browser.get_playwright(&1))

    on_exit(fn ->
      playwrights
      |> Enum.each(fn playwright ->
        Playwright.Browser.close(playwright)
      end)
    end)

    {:ok, %{browsers: browsers}}
  end

  @tag timeout: 60_000
  test "updating peer metadata works and updating track metadata works correctly", %{
    browsers: browsers
  } do
    Enum.each(browsers, &Browser.join(&1, @start_all))

    [sender, receiver] = browsers

    Process.sleep(@warmup_time)

    Browser.click(sender, @update_peer)
    Process.sleep(2_000)

    stats = Browser.get_stats(receiver, @metadata_peer)
    assert %{"peer" => "newMeta"} = stats

    Browser.click(sender, @update_track)
    Process.sleep(2_000)

    stats = Browser.get_stats(receiver, @metadata_track)
    assert "newTrackMeta" = stats
  end

  @tag timeout: 30_000
  test "updating track metadata immediately after adding track works", %{browsers: browsers} do
    browsers_with_start_button = Enum.zip(browsers, [@start_all_update, @start_all])
    [_sender, receiver] = browsers

    Enum.each(browsers_with_start_button, fn {browser, button} ->
      Browser.join(browser, button)
    end)

    Process.sleep(@warmup_time)

    stats = Browser.get_stats(receiver, @metadata_track)
    assert "updatedMetadataOnStart" = stats
  end
end
