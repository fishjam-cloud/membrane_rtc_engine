defmodule Membrane.RTC.Engine.Endpoint.ExWebRTCTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Fishjam.MediaEvents.{Peer, Server}

  alias Fishjam.MediaEvents.Peer.MediaEvent.{
    Connect,
    RenegotiateTracks,
    SdpOffer,
    SetTargetTrackVariant,
    TrackBitrates,
    UnmuteTrack,
    VariantBitrate
  }

  alias Server.MediaEvent.OfferData

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint
  alias Membrane.RTC.Engine.Message
  alias Membrane.RTC.Engine.Track

  alias ExWebRTC.{MediaStreamTrack, PeerConnection, SessionDescription}

  @endpoint_id "endpoint_id"
  @connect_event {:connect, %Connect{metadata_json: Jason.encode!("")}}
  @renegotiate_tracks_event {:renegotiate_tracks, %RenegotiateTracks{}}

  setup do
    {:ok, pid} = Engine.start_link([], [])

    Engine.register(pid, self())

    endpoint = %Endpoint.ExWebRTC{rtc_engine: pid, event_serialization: :protobuf}

    Engine.add_endpoint(pid, endpoint, id: @endpoint_id)

    :erlang.trace(:all, true, [:call])

    :erlang.trace_pattern({Engine, :handle_endpoint_notification, 4}, true, [:local])

    :erlang.trace_pattern({Endpoint.ExWebRTC, :handle_child_playing, 3}, true, [:local])
    :erlang.trace_pattern({Endpoint.ExWebRTC, :handle_media_event, 4}, true, [:local])

    on_exit(fn -> Engine.terminate(pid) end)

    [rtc_engine: pid]
  end

  describe "Send media event" do
    # The `unmute_track` event is used to accelerate the unmuting of tracks that have been muted for an extended period.
    # Each time a track is unmuted on the client side, the client SDK sends an unmute event.
    # Due to this, testing it in the `ex_webrtc` browser integration tests is challenging, thus we test it here.
    test "unmute_track", %{rtc_engine: rtc_engine} do
      pc = connect_peer(rtc_engine)

      # We must ensure that the TrackSender process is alive before we begin tracing it.
      assert_receive {:trace, _pid, :call,
                      {Endpoint.ExWebRTC, :handle_child_playing, [{:track_sender, _}, _, _]}},
                     500

      :erlang.trace_pattern(
        {Endpoint.ExWebRTC.TrackSender, :handle_parent_notification, 3},
        true,
        [:local]
      )

      send_media_event(rtc_engine, {:unmute_track, %UnmuteTrack{track_id: "#{track_id(pc)}"}})

      assert_receive {:trace, _, :call,
                      {Endpoint.ExWebRTC, :handle_media_event, [:unmute_track, _, _, _]}},
                     500

      assert_receive {:trace, _, :call,
                      {Endpoint.ExWebRTC.TrackSender, :handle_parent_notification,
                       [:unmute_track, _, _]}},
                     500

      refute_receive %Message.EndpointCrashed{endpoint_id: @endpoint_id}, 500
    end

    test "set_target_variant with non existing track id", %{rtc_engine: rtc_engine} do
      :ok =
        send_media_event(
          rtc_engine,
          {:set_target_track_variant,
           %SetTargetTrackVariant{track_id: "non-existing", variant: :VARIANT_MEDIUM}}
        )

      assert_receive {:trace, _pid, :call,
                      {Endpoint.ExWebRTC, :handle_media_event,
                       [:set_target_track_variant, _, _, _]}}

      refute_receive %Message.EndpointCrashed{endpoint_id: @endpoint_id}, 500
    end

    test "unmute_track with non existing track id", %{rtc_engine: rtc_engine} do
      :ok = send_media_event(rtc_engine, {:unmute_track, %UnmuteTrack{track_id: "non-existing"}})

      assert_receive {:trace, _pid, :call,
                      {Endpoint.ExWebRTC, :handle_media_event, [:unmute_track, _, _, _]}}

      refute_receive %Message.EndpointCrashed{endpoint_id: @endpoint_id}, 500
    end

    test "returns correct number of track types in case of failed subscription", %{
      rtc_engine: rtc_engine
    } do
      send_media_event(rtc_engine, @connect_event)
      assert {:connected, %Server.MediaEvent.Connected{}} = receive_media_event()

      track =
        Track.new(:video, Track.stream_id(), "fake_endpoint_id", :H264, 90_000, nil,
          id: UUID.uuid4()
        )

      message = {:new_tracks, [track]}
      :ok = Engine.message_endpoint(rtc_engine, @endpoint_id, message)

      assert {:tracks_added, %Server.MediaEvent.TracksAdded{}} = receive_media_event()

      assert {:offer_data, %OfferData{tracks_types: %OfferData.TrackTypes{audio: 0, video: 1}}} =
               receive_media_event()

      {pc, offer} = spawn_peer_connection(outbound_video?: false, inbound_video?: true)

      offer_event = {:sdp_offer, %SdpOffer{sdp: offer.sdp}}
      send_media_event(rtc_engine, offer_event)

      assert {:sdp_answer, %Server.MediaEvent.SdpAnswer{sdp: answer}} = receive_media_event()
      PeerConnection.set_remote_description(pc, %SessionDescription{type: :answer, sdp: answer})

      assert_receive {:ex_webrtc, ^pc, {:connection_state_change, :connected}}, 500

      # The subscription fails, because the endpoint and track don't exists, so track is removed
      assert received_track_removed?()

      send_media_event(rtc_engine, @renegotiate_tracks_event)

      assert {:offer_data, %OfferData{tracks_types: %OfferData.TrackTypes{audio: 0, video: 1}}} =
               receive_media_event()
    end

    defp received_track_removed?() do
      case receive_media_event() do
        {:tracks_removed, %Server.MediaEvent.TracksRemoved{}} -> true
        {:candidate, %Fishjam.MediaEvents.Candidate{}} -> received_track_removed?()
        _media_event -> false
      end
    end

    # Creates `ExWebRTC.PeerConnection` with one video track and connects it to the `Endpoint.ExWebRTC`
    defp connect_peer(rtc_engine) do
      send_media_event(rtc_engine, @connect_event)
      assert {:connected, %Server.MediaEvent.Connected{}} = receive_media_event()

      send_media_event(rtc_engine, @renegotiate_tracks_event)
      assert {:offer_data, %Server.MediaEvent.OfferData{}} = receive_media_event()

      {pc, offer} = spawn_peer_connection()

      offer_event = sdp_offer_event(pc, offer)
      send_media_event(rtc_engine, offer_event)

      assert {:sdp_answer, %Server.MediaEvent.SdpAnswer{sdp: answer}} = receive_media_event()

      PeerConnection.set_remote_description(pc, %SessionDescription{type: :answer, sdp: answer})

      assert_receive {:ex_webrtc, ^pc, {:connection_state_change, :connected}}, 500

      # For `Endpoint.ExWebRTC` to mark track as ready it has to receive at least one rtp packet
      PeerConnection.send_rtp(pc, track_id(pc), ExRTP.Packet.new(<<1, 2, 3>>))

      assert_receive {:trace, _pid, :call,
                      {Engine, :handle_endpoint_notification, [{:track_ready, _, _, _}, _, _, _]}},
                     500

      pc
    end

    # Creates `ExWebRTC.PeerConnection` with one video track
    defp spawn_peer_connection(opts \\ []) do
      {:ok, pc} = PeerConnection.start_link()

      if Keyword.get(opts, :outbound_video?, true) do
        video_track = MediaStreamTrack.new(:video)
        {:ok, _sender} = PeerConnection.add_track(pc, video_track)
      end

      if Keyword.get(opts, :inbound_video?, false) do
        {:ok, _transceiver} = PeerConnection.add_transceiver(pc, :video, direction: :recvonly)
      end

      {:ok, offer} = PeerConnection.create_offer(pc)
      :ok = PeerConnection.set_local_description(pc, offer)

      # After the gathering state is complete, the SDP offer includes ICE candidates.
      # This eliminates the need to send or receive ICE candidates through separate media events to establish a WebRTC connection.
      assert_receive {:ex_webrtc, _pid, {:ice_gathering_state_change, :complete}}, 500

      offer = PeerConnection.get_local_description(pc)

      {pc, offer}
    end

    defp send_media_event(rtc_engine, event) do
      media_event = to_media_event(event)
      :ok = Engine.message_endpoint(rtc_engine, @endpoint_id, media_event)
    end

    defp receive_media_event() do
      assert_receive %Message.EndpointMessage{message: {:media_event, media_event}}, 500
      from_media_event(media_event)
    end

    defp to_media_event(event),
      do: {:media_event, Peer.MediaEvent.encode(%Peer.MediaEvent{content: event})}

    defp from_media_event(event) do
      %Server.MediaEvent{content: event} = Server.MediaEvent.decode(event)
      event
    end

    defp sdp_offer_event(pc, offer) do
      track_id = track_id(pc)

      {:sdp_offer,
       %SdpOffer{
         sdp: offer.sdp,
         track_id_to_metadata_json: %{"#{track_id}" => Jason.encode!("")},
         track_id_to_bitrates: %{
           "#{track_id}" => %TrackBitrates{
             variant_bitrates: [%VariantBitrate{variant: :VARIANT_HIGH, bitrate: 500_000}]
           }
         },
         mid_to_track_id: %{"0" => "#{track_id}"}
       }}
    end

    defp track_id(pc) do
      [%{sender: %{track: %{id: id}}}] = PeerConnection.get_transceivers(pc)
      id
    end
  end
end
