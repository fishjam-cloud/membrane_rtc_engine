defmodule TestVideoroom.Integration.SimulcastTest do
  use TestVideoroomWeb.ConnCase, async: false

  import TestVideoroom.Integration.Utils

  @room_url "http://localhost:4001"

  # in miliseconds
  @warmup_time 5_000

  @start_with_simulcast "start-simulcast"
  @simulcast_inbound_stats "simulcast-inbound-stats"
  @simulcast_outbound_stats "simulcast-outbound-stats"
  @change_own_high "simulcast-local-high-variant"
  @set_peer_encoding_low "simulcast-peer-low-variant"
  @set_peer_encoding_medium "simulcast-peer-medium-variant"

  # max time needed to recognize variant as inactive
  @variant_inactivity_time 2_000
  # max time needed to recognize variant as active
  @variant_activity_time 11_000
  # time needed to request and receive a variant
  @variant_request_time 2_000

  # TODO: right now noop_variant_selector is used so probing is not used
  @probe_times %{low_to_medium: 30_000, low_to_high: 45_000, nil_to_high: 50_000}

  @stats_number 15
  @stats_interval 1_000

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

  # Ensure that participants receive highest available variant
  # In the beginning this is variant :high
  # After disabling it, we switch to :medium
  # And after enabling the :high variant, we switch to it again
  @tag timeout: @max_test_duration
  test "Disabling :high variant and then enabling it" do
    browsers_number = 2

    pid = self()

    receiver = Process.spawn(fn -> receive_stats(browsers_number, pid) end, [:link])

    mustang_options = %{
      target_url: @room_url,
      warmup_time: @warmup_time,
      start_button: @start_with_simulcast,
      receiver: receiver,
      actions: [],
      simulcast_inbound_stats_button: @simulcast_inbound_stats,
      simulcast_outbound_stats_button: @simulcast_outbound_stats,
      id: -1
    }

    sender_actions = [
      {:get_stats, @simulcast_outbound_stats, @stats_number, @stats_interval, tag: :after_warmup},
      {:click, @change_own_high, @variant_inactivity_time + @variant_request_time},
      {:get_stats, @simulcast_outbound_stats, 3, 1_000, tag: :after_disabling_variant_high},
      {:click, @change_own_high, @variant_activity_time + @variant_request_time},
      {:get_stats, @simulcast_outbound_stats, @stats_number, @stats_interval,
       tag: :after_enabling_variant_high}
    ]

    receiver_actions = [
      {:get_stats, @simulcast_inbound_stats, @stats_number, @stats_interval, tag: :after_warmup},
      {:wait, @variant_inactivity_time + @variant_request_time},
      {:get_stats, @simulcast_inbound_stats, 3, 1_000, tag: :after_disabling_variant_high},
      {:wait, @variant_activity_time + @variant_request_time},
      {:get_stats, @simulcast_inbound_stats, @stats_number, @stats_interval,
       tag: :after_enabling_variant_high}
    ]

    actions_with_id = [sender_actions, receiver_actions] |> Enum.with_index()

    tag_to_expected_rid = %{
      after_warmup: "h",
      after_disabling_variant_high: "m",
      after_enabling_variant_high: "h"
    }

    for {actions, browser_id} <- actions_with_id, into: [] do
      specific_mustang = %{
        mustang_options
        | id: browser_id,
          actions: actions
      }

      Task.async(fn ->
        Stampede.start({TestMustang, specific_mustang}, @browser_options)
      end)
    end
    |> Task.await_many(:infinity)

    receive do
      {:stats, stats} ->
        for tag <- Map.keys(tag_to_expected_rid),
            browser_id_to_stats_samples = Map.get(stats, tag) do
          rid = tag_to_expected_rid[tag]

          sender_stats_samples = browser_id_to_stats_samples[0]
          receiver_stats_samples = browser_id_to_stats_samples[1]

          assert_sender_receiver_stats(
            tag,
            rid,
            sender_stats_samples,
            receiver_stats_samples
          )
        end
    end
  end

  @tag timeout: @max_test_duration
  test "changing encoding to low and then returning to medium works correctly " do
    browsers_number = 2

    pid = self()

    receiver = Process.spawn(fn -> receive_stats(browsers_number, pid) end, [:link])

    mustang_options = %{
      target_url: @room_url,
      warmup_time: @warmup_time,
      start_button: @start_with_simulcast,
      receiver: receiver,
      actions: [],
      simulcast_inbound_stats_button: @simulcast_inbound_stats,
      simulcast_outbound_stats_button: @simulcast_outbound_stats,
      id: -1
    }

    receiver_actions = [
      {:get_stats, @simulcast_inbound_stats, @stats_number, @stats_interval, tag: :after_warmup},
      {:click, @set_peer_encoding_low, @variant_request_time},
      {:get_stats, @simulcast_inbound_stats, @stats_number, @stats_interval,
       tag: :after_switching_to_low_en},
      {:click, @set_peer_encoding_medium, @probe_times[:low_to_medium] + @variant_request_time},
      {:get_stats, @simulcast_inbound_stats, @stats_number, @stats_interval,
       tag: :after_switching_to_medium_en}
    ]

    sender_actions = [
      {:get_stats, @simulcast_outbound_stats, @stats_number, @stats_interval, tag: :after_warmup},
      {:wait, @variant_request_time},
      {:get_stats, @simulcast_outbound_stats, @stats_number, @stats_interval,
       tag: :after_switching_to_low_en},
      {:wait, @probe_times[:low_to_medium] + @variant_request_time},
      {:get_stats, @simulcast_outbound_stats, @stats_number, @stats_interval,
       tag: :after_switching_to_medium_en}
    ]

    actions_with_id = [sender_actions, receiver_actions] |> Enum.with_index()

    tag_to_expected_rid = %{
      after_warmup: "h",
      after_switching_to_low_en: "l",
      after_switching_to_medium_en: "m"
    }

    for {actions, browser_id} <- actions_with_id, into: [] do
      specific_mustang = %{
        mustang_options
        | id: browser_id,
          actions: actions
      }

      Task.async(fn ->
        Stampede.start({TestMustang, specific_mustang}, @browser_options)
      end)
    end
    |> Task.await_many(:infinity)

    receive do
      {:stats, stats} ->
        for tag <- Map.keys(tag_to_expected_rid),
            browser_id_to_stats_samples = Map.get(stats, tag) do
          rid = tag_to_expected_rid[tag]

          sender_stats_samples = browser_id_to_stats_samples[0]
          receiver_stats_samples = browser_id_to_stats_samples[1]

          assert_sender_receiver_stats(
            tag,
            rid,
            sender_stats_samples,
            receiver_stats_samples
          )
        end
    end
  end

  defp are_stats_equal(receiver_stats, sender_variant_stats) do
    # According to WebRTC standard, receiver is never aware of simulcast. Sender sends multiple variants to SFU,
    # but SFU is switching between them transparently, forwarding always only one variant to the receiver
    correct_dimensions? =
      receiver_stats["height"] == sender_variant_stats["height"] and
        receiver_stats["width"] == sender_variant_stats["width"]

    correct_dimensions? or sender_variant_stats["qualityLimitationReason"] != "none"
  end

  defp assert_sender_receiver_stats(
         tag,
         receiver_rid,
         sender_stats_samples,
         receiver_stats_samples
       ) do
    # Receiver stat samples are a nested list of lists, so we need to flatten it (there is only one other peer)
    receiver_stats_samples = List.flatten(receiver_stats_samples)

    assert length(sender_stats_samples) == length(receiver_stats_samples)

    # minimal number of consecutive stats that have to be
    # equal. They are counted up to the end meaning
    # [true, true, false] is not the same as
    # [false, true, true] i.e. the first one will
    # always fail as once we start getting equal
    # stats we cannot have regression
    min_equal_stats_number = div(length(sender_stats_samples), 2)

    equal_stats_samples =
      sender_stats_samples
      |> Enum.zip(receiver_stats_samples)
      |> Enum.map(fn {sender_stats, receiver_stats} ->
        are_stats_equal(receiver_stats, sender_stats[receiver_rid])
      end)
      |> Enum.drop_while(fn result -> result == false end)

    if Enum.all?(equal_stats_samples) and length(equal_stats_samples) >= min_equal_stats_number do
      true
    else
      raise """
      Failed on tag: #{tag} should be rid: #{receiver_rid},
      required minimum #{min_equal_stats_number} of consequtive stats to be equal.
      All receiver stats are: #{inspect(receiver_stats_samples, limit: :infinity, pretty: true)}
      All sender stats are: #{inspect(Enum.map(sender_stats_samples, & &1[receiver_rid]), limit: :infinity, pretty: true)}
      """
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
