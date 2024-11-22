defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.MediaEventTest do
  use ExUnit.Case, async: true

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.MediaEvent

  alias ExWebRTC.SessionDescription

  alias Fishjam.MediaEvents.{Candidate, Metadata, MidToTrackId, Peer}

  alias Fishjam.MediaEvents.Peer.MediaEvent.{
    Connect,
    RenegotiateTracks,
    SdpOffer,
    TrackBitrate,
    TrackIdToBitrates,
    TrackIdToMetadata,
    UpdateEndpointMetadata
  }

  alias Fishjam.MediaEvents.Server.MediaEvent.{
    Connected,
    EndpointAdded,
    EndpointRemoved,
    EndpointUpdated,
    EndpointUpdated,
    OfferData,
    SdpAnswer,
    TracksAdded,
    TracksRemoved,
    TrackUpdated,
    VadNotification
  }

  describe "deserializing `connect` media event" do
    test "creates proper map when event is valid" do
      raw_media_event =
        %Peer.MediaEvent{
          content:
            {:connect,
             %Connect{
               metadata: %Metadata{json: Jason.encode!(%{"displayName" => "Bob"})}
             }}
        }
        |> Peer.MediaEvent.encode()

      expected_media_event = %{
        type: :connect,
        data: %{
          metadata: %{"displayName" => "Bob"}
        }
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
    end

    test "returns error when metadata is not a valid json" do
      raw_media_event =
        %Connect{metadata: %Metadata{json: nil}} |> Peer.MediaEvent.encode()

      assert {:error, :invalid_media_event} == MediaEvent.decode(raw_media_event)
    end
  end

  describe "deserializing sdpOffer media event" do
    test "creates proper map when event is valid" do
      metadata = [
        %TrackIdToMetadata{
          track_id: "track_id",
          metadata: %Metadata{json: Jason.encode!(%{"abc" => "cba"})}
        }
      ]

      decoded_metadata = %{"track_id" => %{"abc" => "cba"}}

      bitrates = [
        %TrackIdToBitrates{
          tracks: {:track_bitrate, %TrackBitrate{track_id: "track_id", bitrate: 500_000}}
        }
      ]

      decoded_bitrates = %{"track_id" => %{high: 500_000}}

      mids = [%MidToTrackId{track_id: "track_id", mid: "5"}]
      decoded_mids = %{"5" => "track_id"}

      sdp = "mock_sdp"

      raw_media_event =
        %Peer.MediaEvent{
          content:
            {:sdp_offer,
             %SdpOffer{
               sdp_offer:
                 Jason.encode!(%{
                   "type" => "offer",
                   "sdp" => sdp
                 }),
               track_id_to_metadata: metadata,
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
              sdp: sdp
            },
            track_id_to_track_metadata: decoded_metadata,
            track_id_to_track_bitrates: decoded_bitrates,
            mid_to_track_id: decoded_mids
          }
        }
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
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
             %UpdateEndpointMetadata{
               metadata: %Metadata{json: "{this is not a valid json]"}
             }}
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

      assert {:connected, %Connected{}} =
               event = MediaEvent.connected("myendpoint", [engine_endpoint()], ice_servers)

      assert_action(event)
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
  end

  defp assert_action(event) do
    assert [notify_parent: {:forward_to_parent, {:media_event, message}}] =
             MediaEvent.to_action(event)

    assert is_binary(message)
  end

  defp engine_endpoint() do
    %Engine.Endpoint{
      type: Engine.Endpoint.ExWebRTC,
      id: "endpoint_id",
      metadata: %{display_name: "hello"}
    }
  end
end
