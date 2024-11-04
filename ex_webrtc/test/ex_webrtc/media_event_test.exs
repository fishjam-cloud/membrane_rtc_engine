defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.MediaEventTest do
  use ExUnit.Case, async: true

  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.MediaEvent

  alias Fishjam.MediaEvents.Peer

  alias Fishjam.MediaEvents.Peer.MediaEvent.{
    Connect,
    SdpOffer,
    TrackBitrate,
    TrackIdToBitrates,
    TrackIdToMetadata
  }

  alias Fishjam.MediaEvents.{Metadata, MidToTrackId}

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
          tracks: {:track_bitrate, %TrackBitrate{track_id: "track_id", bitrate: 500}}
        }
      ]

      decoded_bitrates = %{"track_id" => 500}

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
            sdp_offer: %{
              "type" => "offer",
              "sdp" => sdp
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
            sdp_offer: sdp,
            track_id_to_track_metadata: %{},
            track_id_to_track_bitrates: %{},
            mid_to_track_id: %{}
          }
        }
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
    end
  end
end
