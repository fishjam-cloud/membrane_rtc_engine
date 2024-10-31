defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.MediaEvent do
  @moduledoc false

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Track

  alias Fishjam.MediaEvents.{Candidate, MidToTrackId, Peer}

  alias Fishjam.MediaEvents.Peer.MediaEvent.{
    Connect,
    Disconnect,
    RenegotiateTracks,
    SdpOffer,
    UpdateEndpointMetadata,
    UpdateTrackMetadata
  }

  alias Fishjam.MediaEvents.Server

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

  @type t() :: struct()

  @spec connected(Engine.Endpoint.id(), [Engine.Endpoint.t()]) :: t()
  def connected(endpoint_id, other_endpoints) do
    other_endpoints =
      other_endpoints
      |> Enum.map(
        &%Server.MediaEvent.Endpoint{
          endpoint_id: &1.id,
          endpoint_type: to_type_string(&1.type),
          metadata: Jason.encode!(&1.metadata),
          tracks: &1 |> Engine.Endpoint.get_active_tracks() |> to_tracks_info()
        }
      )

    %Connected{
      endpoint_id: endpoint_id,
      endpoints: other_endpoints
    }
  end

  @spec endpoint_added(Engine.Endpoint.t()) :: t()
  def endpoint_added(%Engine.Endpoint{id: id, metadata: metadata}) do
    %EndpointAdded{
      endpoint_id: id,
      metadata: Jason.encode!(metadata)
    }
  end

  @spec endpoint_removed(Engine.Endpoint.id()) :: t()
  def endpoint_removed(endpoint_id) do
    %EndpointRemoved{
      endpoint_id: endpoint_id
    }
  end

  @spec endpoint_updated(Engine.Endpoint.t()) :: t()
  def endpoint_updated(%Engine.Endpoint{id: endpoint_id, metadata: metadata}) do
    %EndpointUpdated{
      endpoint_id: endpoint_id,
      metadata: Jason.encode!(metadata)
    }
  end

  @spec tracks_added(Engine.Endpoint.id(), %{Track.id() => Track.t()}) :: t()
  def tracks_added(endpoint_id, tracks) do
    %TracksAdded{
      endpoint_id: endpoint_id,
      tracks: to_tracks_info(tracks)
    }
  end

  @spec tracks_removed(Engine.Endpoint.id(), [String.t()]) :: t()
  def tracks_removed(endpoint_id, track_ids) do
    %TracksRemoved{
      endpoint_id: endpoint_id,
      track_ids: track_ids
    }
  end

  @spec track_updated(Engine.Endpoint.id(), String.t(), map()) :: t()
  def track_updated(endpoint_id, track_id, metadata) do
    %TrackUpdated{
      endpoint_id: endpoint_id,
      track_id: track_id,
      metadata: Jason.encode!(metadata)
    }
  end

  @spec sdp_answer(ExWebRTC.SessionDescription.t(), %{String.t() => non_neg_integer()}) :: t()
  def sdp_answer(answer, mid_to_track_id) do
    %SdpAnswer{
      sdp_answer: Map.fetch!(answer, "sdp"),
      mid_to_track_id: to_mid_to_track_id(mid_to_track_id)
    }
  end

  @spec offer_data(%{audio: non_neg_integer(), video: non_neg_integer()}) :: t()
  def offer_data(%{audio: audio, video: video}) do
    %OfferData{
      tracks_types: %OfferData.TrackTypes{audio: audio, video: video}
    }
  end

  @spec candidate(ExWebRTC.ICECandidate.t()) :: t()
  def candidate(candidate), do: struct!(Candidate, candidate)

  @spec voice_activity(Track.id(), :speech | :silence) :: t()
  def voice_activity(track_id, vad) do
    %VadNotification{
      track_id: track_id,
      status: to_proto_vad_status(vad)
    }
  end

  @spec to_action(t()) :: [notify_parent: {:forward_to_parent, {:media_event, binary()}}]
  def to_action(event) do
    [notify_parent: {:forward_to_parent, {:media_event, Server.MediaEvent.encode(event)}}]
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, :invalid_media_event}
  def decode(encoded_message) do
    try do
      case Peer.MediaEvent.decode(encoded_message) do
        %{content: {_name, media_event}} -> do_decode(media_event)
        _other -> {:error, :invalid_media_event}
      end
    rescue
      _error in Protobuf.DecodeError ->
        {:error, :invalid_media_event}

      _error in Jason.DecodeError ->
        {:error, :invalid_media_event}
    end
  end

  defp do_decode(%Connect{metadata: metadata}),
    do: {:ok, %{type: :connect, data: %{metadata: Jason.decode!(metadata.json)}}}

  defp do_decode(%Disconnect{}), do: {:ok, %{type: :disconnect}}

  defp do_decode(%UpdateEndpointMetadata{metadata: metadata}),
    do: {:ok, %{type: :update_endpoint_metadata, data: %{metadata: Jason.decode!(metadata.json)}}}

  defp do_decode(%UpdateTrackMetadata{
         track_id: track_id,
         metadata: metadata
       }),
       do:
         {:ok,
          %{
            type: :update_track_metadata,
            data: %{track_id: track_id, track_metadata: Jason.decode!(metadata.json)}
          }}

  defp do_decode(%RenegotiateTracks{}) do
    to_custom(%{type: :renegotiate_tracks})
  end

  defp do_decode(%Candidate{} = event) do
    to_custom(%{
      type: :candidate,
      data: Map.from_struct(event)
    })
  end

  defp do_decode(%SdpOffer{} = event) do
    %{
      sdp_offer: sdp_offer,
      track_id_to_metadata: track_id_to_metadata,
      track_id_to_bitrates: track_id_to_bitrates,
      mid_to_track_id: mid_to_track_id
    } = event

    to_custom(%{
      type: :sdp_offer,
      data: %{
        sdp_offer: Jason.decode!(sdp_offer),
        track_id_to_track_metadata: parse_track_id_to_metadata(track_id_to_metadata),
        track_id_to_track_bitrates: parse_track_id_to_bitrates(track_id_to_bitrates),
        mid_to_track_id: parse_mid_to_track_id(mid_to_track_id)
      }
    })
  end

  defp do_decode(_event), do: {:error, :invalid_media_event}

  defp to_custom(msg) do
    {:ok, %{type: :custom, data: msg}}
  end

  defp to_type_string(type), do: Module.split(type) |> List.last() |> String.downcase()

  defp to_tracks_info(tracks) do
    Enum.map(
      tracks,
      &%Server.MediaEvent.Track{
        track_id: &1.id,
        metadata: &1.metadata
      }
    )
  end

  defp parse_track_id_to_metadata(tracks) do
    Map.new(tracks, fn %{track_id: track_id, metadata: metadata} ->
      {track_id, Jason.decode!(metadata.json)}
    end)
  end

  defp parse_track_id_to_bitrates(bitrates) do
    Map.new(bitrates, fn %{tracks: {:track_bitrate, track_bitrate}} ->
      {track_bitrate.track_id, track_bitrate.bitrate}
    end)
  end

  defp parse_mid_to_track_id(mids) do
    Map.new(mids, &{&1.mid, &1.track_id})
  end

  defp to_mid_to_track_id(mid_to_track_id) do
    Enum.map(mid_to_track_id, fn {mid, track_id} ->
      %MidToTrackId{mid: mid, track_id: track_id}
    end)
  end

  defp to_proto_vad_status(:silence), do: :STATUS_SILENCE
  defp to_proto_vad_status(:speech), do: :STATUS_SPEECH
  defp to_proto_vad_status(_type), do: :STATUS_UNSPECIFIED
end
