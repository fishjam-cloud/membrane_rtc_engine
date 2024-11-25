defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.MediaEventTest do
  use ExUnit.Case, async: true

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.MediaEvent

  alias ExWebRTC.SessionDescription

  alias Fishjam.MediaEvents.{Candidate, Peer}

  alias Fishjam.MediaEvents.Peer.MediaEvent.{
    Connect,
    DisableTrackVariant,
    EnableTrackVariant,
    RenegotiateTracks,
    SdpOffer,
    TrackBitrates,
    UpdateEndpointMetadata,
    VariantBitrate
  }

  alias Fishjam.MediaEvents.Server.MediaEvent.{
    Connected,
    Endpoint,
    EndpointAdded,
    EndpointRemoved,
    EndpointUpdated,
    EndpointUpdated,
    IceServer,
    OfferData,
    SdpAnswer,
    Track,
    TracksAdded,
    TracksRemoved,
    TrackUpdated,
    TrackVariantDisabled,
    TrackVariantEnabled,
    TrackVariantSwitched,
    VadNotification
  }

  @mock_sdp "v=0\r\no=- 52485560578773596 0 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=ice-options:trickle\r\na=group:BUNDLE 0\r\na=extmap-allow-mixed\r\na=msid-semantic:WMS *\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\nc=IN IP4 0.0.0.0\r\na=rtcp:9 IN IP4 0.0.0.0\r\na=sendrecv\r\na=mid:0\r\na=ice-ufrag:W80f\r\na=ice-pwd:5o2HUxiZqwk0gDNDwxRGZg==\r\na=ice-options:trickle\r\na=fingerprint:sha-256 9E:D2:28:2A:C0:03:0B:EE:81:09:38:0B:DE:F2:37:5A:25:46:88:6B:96:FD:C2:A7:72:CF:5F:B7:BD:BC:A6:A0\r\na=setup:actpass\r\na=rtcp-mux\r\na=extmap:1 urn:ietf:params:rtp-hdrext:sdes:mid\r\na=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\na=rtpmap:111 opus/48000/2\r\na=rtcp-fb:111 transport-cc\r\n"

  describe "deserializing `connect` media event" do
    test "creates proper map when event is valid" do
      raw_media_event =
        %Peer.MediaEvent{
          content: {:connect, %Connect{metadata_json: Jason.encode!(%{"displayName" => "Bob"})}}
        }
        |> Peer.MediaEvent.encode()

      expected_media_event = %{
        type: :connect,
        data: %{metadata: %{"displayName" => "Bob"}}
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
    end

    test "returns error when metadata is not a valid json" do
      raw_media_event =
        %Connect{metadata_json: nil} |> Peer.MediaEvent.encode()

      assert {:error, :invalid_media_event} == MediaEvent.decode(raw_media_event)
    end
  end

  describe "deserializing sdpOffer media event" do
    test "valid event - non simulcast track" do
      bitrates = %{
        "track_id" => %TrackBitrates{
          variant_bitrates: [%VariantBitrate{variant: :VARIANT_HIGH, bitrate: 500_000}]
        }
      }

      decoded_bitrates = %{"track_id" => %{high: 500_000}}

      test_decode_sdp_offer(bitrates, decoded_bitrates)
    end

    test "valid event - simulcast track" do
      raw_variant_bitrates = %{low: 150_000, medium: 500_000, high: 1_500_000}

      bitrates = %{"track_id" => %TrackBitrates{variant_bitrates: variant_bitrates()}}

      decoded_bitrates = %{"track_id" => raw_variant_bitrates}

      test_decode_sdp_offer(bitrates, decoded_bitrates)
    end

    test "is ok when event misses key" do
      sdp = %{
        "type" => "offer",
        "sdp" => "mock_sdp"
      }

      raw_media_event =
        %Peer.MediaEvent{
          content:
            {:sdp_offer,
             %SdpOffer{
               sdp_offer: Jason.encode!(sdp)
             }}
        }
        |> Peer.MediaEvent.encode()

      expected_media_event = %{
        type: :custom,
        data: %{
          type: :sdp_offer,
          data: %{
            sdp_offer: %SessionDescription{type: :offer, sdp: "mock_sdp"},
            track_id_to_track_metadata: %{},
            track_id_to_track_bitrates: %{},
            mid_to_track_id: %{}
          }
        }
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
    end
  end

  describe "deserializing invalid media event" do
    test "invalid protobuf" do
      raw_media_event = "this is not a real event"

      assert {:error, :invalid_media_event} == MediaEvent.decode(raw_media_event)
    end

    test "invalid metadata" do
      raw_media_event =
        %Peer.MediaEvent{
          content:
            {:update_endpoint_metadata,
             %UpdateEndpointMetadata{metadata_json: "{this is not a valid json]"}}
        }
        |> Peer.MediaEvent.encode()

      assert {:error, :invalid_media_event} == MediaEvent.decode(raw_media_event)
    end
  end

  describe "deserializing ICE candidate" do
    test "deserializing correct event" do
      candidate = %{
        candidate: "ICE candidate",
        sdp_m_line_index: 4,
        sdp_mid: "2",
        username_fragment: "user fragment"
      }

      raw_media_event =
        %Peer.MediaEvent{
          content: {:candidate, struct!(Candidate, candidate)}
        }
        |> Peer.MediaEvent.encode()

      expected_candidate = %ExWebRTC.ICECandidate{
        candidate: "ICE candidate",
        sdp_m_line_index: 4,
        sdp_mid: "2",
        username_fragment: "user fragment"
      }

      expected_media_event = %{
        type: :custom,
        data: %{
          type: :candidate,
          data: expected_candidate
        }
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
    end
  end

  describe "deserializing renegotiate tracks" do
    test "deserializing correct event" do
      raw_media_event =
        %Peer.MediaEvent{
          content: {:renegotiate_tracks, %RenegotiateTracks{}}
        }
        |> Peer.MediaEvent.encode()

      expected_media_event = %{
        type: :custom,
        data: %{type: :renegotiate_tracks}
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
    end
  end

  describe "deserializing simulcast events" do
    test "enable_track_variant" do
      raw_media_event =
        %Peer.MediaEvent{
          content:
            {:enable_track_variant,
             %EnableTrackVariant{track_id: "track_id", variant: :VARIANT_MEDIUM}}
        }
        |> Peer.MediaEvent.encode()

      expected_media_event = %{
        type: :enable_track_variant,
        data: %{track_id: "track_id", variant: :medium}
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
    end

    test "disable_track_variant" do
      raw_media_event =
        %Peer.MediaEvent{
          content:
            {:disable_track_variant,
             %DisableTrackVariant{track_id: "track_id", variant: :VARIANT_MEDIUM}}
        }
        |> Peer.MediaEvent.encode()

      expected_media_event = %{
        type: :disable_track_variant,
        data: %{track_id: "track_id", variant: :medium}
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
    end

    test "track_bitrate" do
      raw_media_event =
        %Peer.MediaEvent{
          content:
            {:track_bitrates,
             %TrackBitrates{track_id: "track_id", variant_bitrates: variant_bitrates()}}
        }
        |> Peer.MediaEvent.encode()

      expected_media_event = %{
        type: :custom,
        data: %{
          type: :track_bitrate,
          data: %{
            track_id: "track_id",
            bitrates: %{low: 150_000, medium: 500_000, high: 1_500_000}
          }
        }
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
    end
  end

  describe "serializing invalid media events" do
    test "invalid metadata" do
      endpoint = %Engine.Endpoint{type: "ex_webrtc", id: "endpoint_id", metadata: "\xFF"}

      assert_raise(Jason.EncodeError, fn -> MediaEvent.endpoint_added(endpoint) end)
    end
  end

  describe "serializing valid media events" do
    test "connected" do
      ice_servers = [
        %{urls: ["stun:stun.l.google.com:19302"]},
        %{urls: ["turns:turns.example.com:5349", "turns:turns.example.com:5347"]},
        %{
          urls: "turn:turn.example.com:3478",
          username: "user123",
          credential: "password123"
        }
      ]

      assert {:connected, %Connected{} = connected} =
               event =
               MediaEvent.connected(
                 "myendpoint",
                 [engine_endpoint(id: "myendpoint")],
                 ice_servers
               )

      assert_action(event)

      assert %Connected{
               endpoint_id: "myendpoint",
               endpoint_id_to_endpoint: %{
                 "myendpoint" => %Endpoint{
                   endpoint_type: "exwebrtc",
                   metadata_json: Jason.encode!(%{display_name: "hello"}),
                   track_id_to_track: %{
                     "track_id" => %Track{
                       metadata_json: Jason.encode!(%{trackName: "my_track"}),
                       simulcast_config: %Track.SimulcastConfig{
                         enabled: true,
                         enabled_variants: [:VARIANT_LOW, :VARIANT_MEDIUM, :VARIANT_HIGH],
                         disabled_variants: []
                       }
                     }
                   }
                 }
               },
               ice_servers: connected.ice_servers
             } == connected

      assert not Enum.empty?(connected.ice_servers) and
               Enum.all?(connected.ice_servers, &is_struct(&1, IceServer))
    end

    test "endpoint_added" do
      assert {:endpoint_added, %EndpointAdded{}} =
               event = MediaEvent.endpoint_added(engine_endpoint())

      assert_action(event)
    end

    test "endpoint_removed" do
      assert {:endpoint_removed, %EndpointRemoved{}} =
               event = MediaEvent.endpoint_removed("endpoint_id")

      assert_action(event)
    end

    test "endpoint_updated" do
      assert {:endpoint_updated, %EndpointUpdated{}} =
               event = MediaEvent.endpoint_updated(engine_endpoint())

      assert_action(event)
    end

    test "tracks_added" do
      track = Engine.Track.new(:audio, "strem_id", "origin", "H264", 16_000, nil)

      assert {:tracks_added, %TracksAdded{}} =
               event = MediaEvent.tracks_added("endpoint_id", [track])

      assert_action(event)
    end

    test "tracks_removed" do
      assert {:tracks_removed, %TracksRemoved{}} =
               event = MediaEvent.tracks_removed("endpoint_id", ["track_id"])

      assert_action(event)
    end

    test "track_updated" do
      assert {:track_updated, %TrackUpdated{}} =
               event = MediaEvent.track_updated("endpoint_id", "track_id", "new_meta")

      assert_action(event)
    end

    test "sdp_answer" do
      sdp =
        SessionDescription.to_json(%SessionDescription{
          sdp: "sdp",
          type: :answer
        })

      assert {:sdp_answer, %SdpAnswer{}} =
               event =
               MediaEvent.sdp_answer(%SessionDescription{sdp: sdp, type: :answer}, %{
                 "mid" => "track_id"
               })

      assert_action(event)
    end

    test "offer_data" do
      assert {:offer_data, %OfferData{}} = event = MediaEvent.offer_data(%{audio: 1, video: 3})
      assert_action(event)
    end

    test "candidate" do
      candidate = %ExWebRTC.ICECandidate{
        candidate: "ICE candidate",
        sdp_m_line_index: 4,
        sdp_mid: "2",
        username_fragment: "user fragment"
      }

      assert {:candidate, %Candidate{}} = event = MediaEvent.candidate(candidate)
      assert_action(event)
    end

    test "voice_activity" do
      assert {:vad_notification, %VadNotification{}} =
               event = MediaEvent.voice_activity("track_id", :speech)

      assert_action(event)

      assert {:vad_notification, %VadNotification{}} =
               event = MediaEvent.voice_activity("track_id", :silence)

      assert_action(event)

      assert {:vad_notification, %VadNotification{}} =
               event = MediaEvent.voice_activity("track_id", :unknown)

      assert_action(event)
    end

    test "track_variant_switched" do
      assert {:track_variant_switched, %TrackVariantSwitched{}} =
               event = MediaEvent.track_variant_switched("endpoint_id", "track_id", :medium)

      assert_action(event)
    end

    test "track_variant_enabled" do
      assert {:track_variant_enabled, %TrackVariantEnabled{}} =
               event = MediaEvent.track_variant_enabled("endpoint_id", "track_id", :medium)

      assert_action(event)
    end

    test "track_variant_disabled" do
      assert {:track_variant_disabled, %TrackVariantDisabled{}} =
               event = MediaEvent.track_variant_disabled("endpoint_id", "track_id", :medium)

      assert_action(event)
    end
  end

  defp test_decode_sdp_offer(bitrates, expected_bitrates) do
    metadata = %{"track_id" => Jason.encode!(%{"abc" => "cba"})}

    decoded_metadata = %{"track_id" => %{"abc" => "cba"}}

    mids = %{"5" => "track_id"}

    raw_media_event =
      %Peer.MediaEvent{
        content:
          {:sdp_offer,
           %SdpOffer{
             sdp_offer:
               Jason.encode!(%{
                 "type" => "offer",
                 "sdp" => @mock_sdp
               }),
             track_id_to_metadata_json: metadata,
             track_id_to_bitrates: bitrates,
             mid_to_track_id: mids
           }}
      }
      |> Peer.MediaEvent.encode()

    expected_media_event = %{
      type: :custom,
      data: %{
        type: :sdp_offer,
        data: %{
          sdp_offer: %SessionDescription{
            type: :offer,
            sdp: @mock_sdp
          },
          track_id_to_track_metadata: decoded_metadata,
          track_id_to_track_bitrates: expected_bitrates,
          mid_to_track_id: mids
        }
      }
    }

    assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
  end

  defp assert_action(event) do
    assert [notify_parent: {:forward_to_parent, {:media_event, message}}] =
             MediaEvent.to_action(event)

    assert is_binary(message)
  end

  defp engine_endpoint(opts \\ []) do
    %Engine.Endpoint{
      type: Engine.Endpoint.ExWebRTC,
      id: Keyword.get(opts, :id, "endpoint_id"),
      metadata: %{display_name: "hello"},
      inbound_tracks: %{
        "track_id" =>
          Engine.Track.new(
            :video,
            "stream_id",
            "endpoint_id",
            :H264,
            90_000,
            nil,
            id: "track_id",
            metadata: %{trackName: "my_track"},
            variants: [:low, :medium, :high]
          )
      }
    }
  end

  defp variant_bitrates() do
    Enum.map(
      [VARIANT_LOW: 150_000, VARIANT_MEDIUM: 500_000, VARIANT_HIGH: 1_500_000],
      fn {variant, bitrate} -> %VariantBitrate{variant: variant, bitrate: bitrate} end
    )
  end
end
