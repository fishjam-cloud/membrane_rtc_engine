defmodule Membrane.RTC.Engine.Endpoint.ExWebRTCTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Fishjam.MediaEvents.Peer
  alias Fishjam.MediaEvents.Peer.MediaEvent.{SetTargetTrackVariant, UnmuteTrack}

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC
  alias Membrane.RTC.Engine.Message

  @endpoint_id "endpoint_id"

  setup do
    {:ok, pid} = Engine.start_link([], [])

    Engine.register(pid, self())

    endpoint = %ExWebRTC{rtc_engine: pid, event_serialization: :protobuf}

    Engine.add_endpoint(pid, endpoint, id: @endpoint_id)

    on_exit(fn -> Engine.terminate(pid) end)

    [rtc_engine: pid]
  end

  describe "Send media event" do
    test "set_target_variant with non existing track id", %{rtc_engine: engine} do
      media_event =
        to_media_event(
          {:set_target_track_variant,
           %SetTargetTrackVariant{track_id: "non-existing", variant: :VARIANT_MEDIUM}}
        )

      Engine.message_endpoint(engine, @endpoint_id, media_event)

      refute_receive %Message.EndpointCrashed{endpoint_id: @endpoint_id, endpoint_type: ExWebRTC},
                     500
    end

    test "unmute_track with non existing track id", %{rtc_engine: engine} do
      media_event = to_media_event({:unmute_track, %UnmuteTrack{track_id: "non-existing"}})

      Engine.message_endpoint(engine, @endpoint_id, media_event)

      refute_receive %Message.EndpointCrashed{endpoint_id: @endpoint_id, endpoint_type: ExWebRTC},
                     500
    end

    defp to_media_event(event),
      do: {:media_event, Peer.MediaEvent.encode(%Peer.MediaEvent{content: event})}
  end
end
