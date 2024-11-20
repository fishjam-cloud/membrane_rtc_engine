defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.MediaEventJsonTest do
  use ExUnit.Case, async: true

  alias ExWebRTC.SessionDescription

  alias Membrane.RTC.Engine.Endpoint
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.MediaEventJson, as: MediaEvent

  describe "deserializing `connect` media event" do
    test "creates proper map when event is valid" do
      raw_media_event =
        %{
          "type" => "connect",
          "data" => %{
            "receiveMedia" => true,
            "metadata" => %{"displayName" => "Bob"}
          }
        }
        |> Jason.encode!()

      expected_media_event = %{
        type: :connect,
        data: %{
          metadata: %{"displayName" => "Bob"}
        }
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
    end

    test "returns error when event misses key" do
      raw_media_event =
        %{
          "type" => "join",
          "data" =>
            %{
              # missing metadata field
            }
        }
        |> Jason.encode!()

      assert {:error, :invalid_media_event} == MediaEvent.decode(raw_media_event)
    end
  end

  describe "deserializing sdpOffer media event" do
    test "creates proper map when event is valid" do
      metadata = %{"track_id" => %{"abc" => "cba"}}
      bitrates = %{"track_id" => %{"m" => 200, "h" => 500, "l" => 100}}
      decoded_bitrates = %{"track_id" => %{medium: 200, high: 500, low: 100}}
      mids = %{"5" => "track_id"}
      sdp = "mock_sdp"

      raw_media_event =
        %{
          "type" => "custom",
          "data" => %{
            "type" => "sdpOffer",
            "data" => %{
              "sdpOffer" => %{
                "type" => "offer",
                "sdp" => sdp
              },
              "trackIdToTrackMetadata" => metadata,
              "trackIdToTrackBitrates" => bitrates,
              "midToTrackId" => mids
            }
          }
        }
        |> Jason.encode!()

      expected_media_event = %{
        type: :custom,
        data: %{
          type: :sdp_offer,
          data: %{
            sdp_offer: %SessionDescription{type: :offer, sdp: sdp},
            track_id_to_track_metadata: metadata,
            track_id_to_track_bitrates: decoded_bitrates,
            mid_to_track_id: mids
          }
        }
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
    end

    test "returns error when event misses key" do
      raw_media_event =
        %{
          "type" => "custom",
          "data" => %{
            "type" => "sdpOffer",
            "data" => %{
              "sdpOffer" => %{
                "type" => "offer",
                "sdp" => "mock_sdp"
              }
            }
          }
        }
        |> Jason.encode!()

      assert {:error, :invalid_media_event} == MediaEvent.decode(raw_media_event)
    end
  end

  describe "deserializing trackVariantBitrates media event" do
    test "creates proper map when event is valid" do
      track_id = "track_id"
      bitrates = %{"h" => 1000, "m" => 500, "l" => 100}
      decoded_bitrates = %{high: 1000, medium: 500, low: 100}

      raw_media_event =
        %{
          "type" => "custom",
          "data" => %{
            "type" => "trackVariantBitrates",
            "data" => %{
              "trackId" => track_id,
              "variantBitrates" => bitrates
            }
          }
        }
        |> Jason.encode!()

      expected_media_event = %{
        type: :custom,
        data: %{
          type: :track_variant_bitrates,
          data: %{
            track_id: track_id,
            variant_bitrates: decoded_bitrates
          }
        }
      }

      assert {:ok, expected_media_event} == MediaEvent.decode(raw_media_event)
    end

    test "returns error when event misses key" do
      raw_media_event =
        %{
          "type" => "custom",
          "data" => %{
            "type" => "trackVariantBitrates",
            "data" => %{
              "trackId" => "track_id"
            }
          }
        }
        |> Jason.encode!()

      assert {:error, :invalid_media_event} == MediaEvent.decode(raw_media_event)
    end
  end

  describe "deserializing ICE candidate" do
    test "deserializing correct event" do
      raw_media_event =
        %{
          "type" => "custom",
          "data" => %{
            "type" => "candidate",
            "data" => %{
              "candidate" => "ICE candidate",
              "sdpMLineIndex" => 4,
              "sdpMid" => "2",
              "usernameFragment" => "user fragment"
            }
          }
        }
        |> Jason.encode!()

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

  describe "serializing connected media event" do
    test "removes endpoint with the same id as endpoint_id" do
      endpoint_id = "endpoint_id"

      other_endpoints = [
        Endpoint.new(endpoint_id, ExWebRTC, []),
        Endpoint.new("other_endpoint", ExWebRTC, [])
      ]

      assert %{
               type: "connected",
               data: %{
                 id: ^endpoint_id,
                 otherEndpoints: [%{id: "other_endpoint"}]
               }
             } = MediaEvent.connected(endpoint_id, other_endpoints)
    end
  end

  describe "serializing sdpAnswer media event" do
    test "parses valid event" do
      answer = %SessionDescription{type: :answer, sdp: "mock_sdp"}
      mid_to_track_id = %{"2" => "track_id"}

      expected_media_event = %{
        type: "custom",
        data: %{
          type: "sdpAnswer",
          data: %{
            "type" => "answer",
            "sdp" => "mock_sdp",
            "midToTrackId" => %{"2" => "track_id"}
          }
        }
      }

      assert expected_media_event == MediaEvent.sdp_answer(answer, mid_to_track_id)
    end
  end
end
