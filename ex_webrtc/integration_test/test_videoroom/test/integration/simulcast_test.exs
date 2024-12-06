defmodule TestVideoroom.Integration.SimulcastTest do
  use TestVideoroomWeb.ConnCase, async: false

  import TestVideoroom.Utils

  alias TestVideoroom.Browser

  @start_with_simulcast "start-simulcast"

  @stats "stats"
  @simulcast_inbound_stats "simulcast-inbound-stats"
  @simulcast_outbound_stats "simulcast-outbound-stats"

  @change_own_high "simulcast-local-high-variant"
  @set_peer_encoding_low "simulcast-peer-low-variant"
  @set_peer_encoding_medium "simulcast-peer-medium-variant"

  # max time needed to recognize variant as inactive
  @variant_inactivity_time 2_000
  # max time needed to recognize variant as active
  @variant_activity_time 13_000
  # time needed to request and receive a variant
  @variant_request_time 2_000

  @warmup_time 10_000
  @stats_number 10

  @browser_options %{target_url: "http://localhost:4001", receiver: nil, id: -1, headless: true}

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

    Enum.each(browsers, fn browser ->
      Browser.join(browser, @start_with_simulcast)
      Process.sleep(@warmup_time)
    end)

    {:ok, %{browsers: browsers}}
  end

  @tag timeout: 40_000
  test "Participants receive audio and video when using simulcast", %{browsers: browsers} do
    assertion_function = fn stats_list ->
      Enum.each(stats_list, fn stats ->
        assert count_playing_streams(stats, "audio") == 1
        assert count_playing_streams(stats, "video") == 1
      end)
    end

    assert_stats(browsers, @stats, 1, assertion_function)
    Process.sleep(20_000)
    assert_stats(browsers, @stats, 1, assertion_function)
  end

  # Ensure that participants receive highest available variant
  # In the beginning this is variant :high
  # After disabling it, we switch to :medium
  # And after enabling the :high variant, we switch to it again

  @tag timeout: 120_000
  test "Disabling :high variant and then enabling it", %{browsers: browsers} do
    [sender, _receiver] = browsers
    buttons = [@simulcast_outbound_stats, @simulcast_inbound_stats]

    assertion_function = fn tag, rid ->
      fn [sender_stats, receiver_stats] ->
        assert_sender_receiver_stats(tag, rid, sender_stats, receiver_stats)
      end
    end

    assert_stats(browsers, buttons, @stats_number, assertion_function.(:after_warmup, "h"))

    Browser.click(sender, @change_own_high)
    Process.sleep(@variant_inactivity_time + @variant_request_time)

    assert_stats(
      browsers,
      buttons,
      @stats_number,
      assertion_function.(:after_disabling_variant_high, "m")
    )

    Browser.click(sender, @change_own_high)
    Process.sleep(@variant_activity_time + @variant_request_time)

    assert_stats(
      browsers,
      buttons,
      @stats_number,
      assertion_function.(:after_enabling_variant_high, "h")
    )
  end

  @tag timeout: 180_000
  test "changing encoding to low and then returning to medium works correctly", %{
    browsers: browsers
  } do
    [_sender, receiver] = browsers
    buttons = [@simulcast_outbound_stats, @simulcast_inbound_stats]

    assertion_function = fn tag, rid ->
      fn [sender, receiver] ->
        assert_sender_receiver_stats(tag, rid, sender, receiver)
      end
    end

    assert_stats(browsers, buttons, @stats_number, assertion_function.(:after_warmup, "h"))

    Browser.click(receiver, @set_peer_encoding_low)
    Process.sleep(@variant_inactivity_time + @variant_request_time)

    assert_stats(
      browsers,
      buttons,
      @stats_number,
      assertion_function.(:after_switching_to_low_en, "l")
    )

    Browser.click(receiver, @set_peer_encoding_medium)
    Process.sleep(@variant_activity_time + @variant_request_time)

    assert_stats(
      browsers,
      buttons,
      @stats_number,
      assertion_function.(:after_switching_to_medium_en, "m")
    )
  end

  defp are_stats_equal(receiver_stats, sender_variant_stats) do
    # According to WebRTC standard, receiver is never aware of simulcast. Sender sends multiple variants to SFU,
    # but SFU is switching between them transparently, forwarding always only one variant to the receiver
    correct_dimensions? =
      receiver_stats["height"] == sender_variant_stats["height"] and
        receiver_stats["width"] == sender_variant_stats["width"]

    simmilar_frame_number? =
      sender_variant_stats["framesSent"] - receiver_stats["framesReceived"] < 200

    correct_dimensions? and simmilar_frame_number?
  end

  defp assert_sender_receiver_stats(
         tag,
         receiver_rid,
         sender_stats_sample,
         [receiver_stats_sample]
       ) do
    error_msg = """
    Failed on tag: #{tag} should be rid: #{receiver_rid},
    Sender sample: #{inspect(sender_stats_sample, limit: :infinity, pretty: true)}
    Receiver sample: #{inspect(receiver_stats_sample, limit: :infinity, pretty: true)}
    """

    assert are_stats_equal(receiver_stats_sample, sender_stats_sample[receiver_rid]), error_msg
  end
end
