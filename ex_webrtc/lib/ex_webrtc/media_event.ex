defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.MediaEvent do
  @moduledoc false

  alias Membrane.RTC.Engine

  alias ExWebRTC.PeerConnection.Configuration
  alias ExWebRTC.SessionDescription

  alias Fishjam.MediaEvents.{Candidate, Peer, Server}

  alias Fishjam.MediaEvents.Peer.MediaEvent.{
    Connect,
    DisableTrackVariant,
    Disconnect,
    EnableTrackVariant,
    RenegotiateTracks,
    SetTargetTrackVariant,
    SdpOffer,
    TrackBitrates,
    UpdateEndpointMetadata,
    UpdateTrackMetadata
  }

  alias Fishjam.MediaEvents.Server.MediaEvent.{
    Connected,
    EndpointAdded,
    EndpointRemoved,
    EndpointUpdated,
    EndpointUpdated,
    IceServer,
    OfferData,
    SdpAnswer,
    TracksAdded,
    TracksRemoved,
    TrackUpdated,
    TrackVariantDisabled,
    TrackVariantEnabled,
    TrackVariantSwitched,
    VadNotification
  }

  @type t() :: {atom(), struct()}

  @err_invalid_event {:error, :invalid_media_event}

  @spec connected(Engine.Endpoint.id(), [Engine.Endpoint.t()], [Configuration.ice_server()]) ::
          t()
  def connected(endpoint_id, endpoints, ice_servers) do
    endpoints =
      Map.new(endpoints, fn endpoint ->
        {endpoint.id,
         %Server.MediaEvent.Endpoint{
           endpoint_type: to_type_string(endpoint.type),
           metadata_json: Jason.encode!(endpoint.metadata),
           track_id_to_track: endpoint |> Engine.Endpoint.get_active_tracks() |> to_tracks_info()
         }}
      end)

    ice_servers = parse_ice_servers(ice_servers)

    {:connected,
     %Connected{
       endpoint_id: endpoint_id,
       endpoint_id_to_endpoint: endpoints,
       ice_servers: ice_servers
     }}
  end

  @spec endpoint_added(Engine.Endpoint.t()) :: t()
  def endpoint_added(%Engine.Endpoint{id: id, metadata: metadata}) do
    {:endpoint_added,
     %EndpointAdded{
       endpoint_id: id,
       metadata_json: Jason.encode!(metadata)
     }}
  end

  @spec endpoint_removed(Engine.Endpoint.id()) :: t()
  def endpoint_removed(endpoint_id) do
    {:endpoint_removed,
     %EndpointRemoved{
       endpoint_id: endpoint_id
     }}
  end

  @spec endpoint_updated(Engine.Endpoint.t()) :: t()
  def endpoint_updated(%Engine.Endpoint{id: endpoint_id, metadata: metadata}) do
    {:endpoint_updated,
     %EndpointUpdated{
       endpoint_id: endpoint_id,
       metadata_json: Jason.encode!(metadata)
     }}
  end

  @spec tracks_added(Engine.Endpoint.id(), [Engine.Track.t()]) :: t()
  def tracks_added(endpoint_id, tracks) do
    {:tracks_added,
     %TracksAdded{
       endpoint_id: endpoint_id,
       track_id_to_track: to_tracks_info(tracks)
     }}
  end

  @spec tracks_removed(Engine.Endpoint.id(), [String.t()]) :: t()
  def tracks_removed(endpoint_id, track_ids) do
    {:tracks_removed,
     %TracksRemoved{
       endpoint_id: endpoint_id,
       track_ids: track_ids
     }}
  end

  @spec track_updated(Engine.Endpoint.id(), String.t(), map()) :: t()
  def track_updated(endpoint_id, track_id, metadata) do
    {:track_updated,
     %TrackUpdated{
       endpoint_id: endpoint_id,
       track_id: track_id,
       metadata_json: Jason.encode!(metadata)
     }}
  end

  @spec sdp_answer(SessionDescription.t(), %{String.t() => non_neg_integer()}) :: t()
  def sdp_answer(answer, mid_to_track_id) do
    {:sdp_answer, %SdpAnswer{sdp: answer.sdp, mid_to_track_id: mid_to_track_id}}
  end

  @spec offer_data(%{audio: non_neg_integer(), video: non_neg_integer()}) :: t()
  def offer_data(%{audio: audio, video: video}) do
    {:offer_data,
     %OfferData{
       tracks_types: %OfferData.TrackTypes{audio: audio, video: video}
     }}
  end

  @spec candidate(ExWebRTC.ICECandidate.t()) :: t()
  def candidate(candidate) do
    candidate = candidate |> Map.from_struct() |> then(&struct!(Candidate, &1))

    {:candidate, candidate}
  end

  @spec voice_activity(Engine.Track.id(), :speech | :silence) :: t()
  def voice_activity(track_id, vad) do
    {:vad_notification,
     %VadNotification{
       track_id: track_id,
       status: to_proto_vad_status(vad)
     }}
  end

  @spec track_variant_switched(Engine.Endpoint.id(), Engine.Track.id(), Engine.Track.variant()) ::
          t()
  def track_variant_switched(endpoint_id, track_id, variant) do
    {:track_variant_switched,
     %TrackVariantSwitched{
       endpoint_id: endpoint_id,
       track_id: track_id,
       variant: to_proto_variant(variant)
     }}
  end

  @spec track_variant_disabled(Engine.Endpoint.id(), Engine.Track.id(), Engine.Track.variant()) ::
          t()
  def track_variant_disabled(endpoint_id, track_id, variant) do
    {:track_variant_disabled,
     %TrackVariantDisabled{
       endpoint_id: endpoint_id,
       track_id: track_id,
       variant: to_proto_variant(variant)
     }}
  end

  @spec track_variant_enabled(Engine.Endpoint.id(), Engine.Track.id(), Engine.Track.variant()) ::
          t()
  def track_variant_enabled(endpoint_id, track_id, variant) do
    {:track_variant_enabled,
     %TrackVariantEnabled{
       endpoint_id: endpoint_id,
       track_id: track_id,
       variant: to_proto_variant(variant)
     }}
  end

  @spec to_action(t()) :: [notify_parent: {:forward_to_parent, {:media_event, binary()}}]
  def to_action(event) do
    event = %Server.MediaEvent{content: event}
    [notify_parent: {:forward_to_parent, {:media_event, Server.MediaEvent.encode(event)}}]
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, :invalid_media_event}
  def decode(encoded_message) do
    try do
      case Peer.MediaEvent.decode(encoded_message) do
        %{content: {_name, media_event}} -> do_decode(media_event)
        _other -> @err_invalid_event
      end
    rescue
      _error in [Protobuf.DecodeError, Jason.DecodeError, FunctionClauseError] ->
        @err_invalid_event
    end
  end

  defp do_decode(%Connect{metadata_json: nil}),
    do: @err_invalid_event

  defp do_decode(%Connect{metadata_json: metadata_json}),
    do: {:ok, %{type: :connect, data: %{metadata: Jason.decode!(metadata_json)}}}

  defp do_decode(%Disconnect{}), do: {:ok, %{type: :disconnect}}

  defp do_decode(%UpdateEndpointMetadata{metadata_json: metadata_json}),
    do: {:ok, %{type: :update_endpoint_metadata, data: %{metadata: Jason.decode!(metadata_json)}}}

  defp do_decode(%DisableTrackVariant{track_id: track_id, variant: variant}) do
    {:ok,
     %{
       type: :disable_track_variant,
       data: %{track_id: track_id, variant: from_proto_variant(variant)}
     }}
  end

  defp do_decode(%EnableTrackVariant{track_id: track_id, variant: variant}) do
    {:ok,
     %{
       type: :enable_track_variant,
       data: %{track_id: track_id, variant: from_proto_variant(variant)}
     }}
  end

  defp do_decode(%SetTargetTrackVariant{track_id: track_id, variant: variant}) do
    {:ok,
     %{
       type: :set_target_track_variant,
       data: %{track_id: track_id, variant: from_proto_variant(variant)}
     }}
  end

  defp do_decode(%UpdateTrackMetadata{
         track_id: track_id,
         metadata_json: metadata_json
       }),
       do:
         {:ok,
          %{
            type: :update_track_metadata,
            data: %{track_id: track_id, track_metadata: Jason.decode!(metadata_json)}
          }}

  defp do_decode(%RenegotiateTracks{}) do
    to_custom(%{type: :renegotiate_tracks})
  end

  defp do_decode(%Candidate{} = event) do
    candidate = event |> Map.from_struct() |> then(&struct(ExWebRTC.ICECandidate, &1))

    to_custom(%{type: :candidate, data: candidate})
  end

  defp do_decode(%SdpOffer{} = event) do
    %{
      sdp: sdp,
      track_id_to_metadata_json: track_id_to_metadata,
      track_id_to_bitrates: track_id_to_bitrates,
      mid_to_track_id: mid_to_track_id
    } = event

    to_custom(%{
      type: :sdp_offer,
      data: %{
        sdp_offer: %SessionDescription{sdp: sdp, type: :offer},
        track_id_to_track_metadata: parse_track_id_to_metadata(track_id_to_metadata),
        track_id_to_track_bitrates: parse_track_id_to_bitrates(track_id_to_bitrates),
        mid_to_track_id: mid_to_track_id
      }
    })
  end

  defp do_decode(%TrackBitrates{track_id: track_id, variant_bitrates: bitrates}) do
    to_custom(%{
      type: :track_bitrate,
      data: %{
        track_id: track_id,
        bitrates: parse_bitrates(bitrates)
      }
    })
  end

  defp do_decode(_event), do: @err_invalid_event

  defp to_custom(msg) do
    {:ok, %{type: :custom, data: msg}}
  end

  defp to_type_string(type), do: Module.split(type) |> List.last() |> String.downcase()

  defp to_tracks_info(tracks) do
    Map.new(tracks, fn track ->
      {track.id,
       %Server.MediaEvent.Track{
         metadata_json: Jason.encode!(track.metadata),
         simulcast_config: simulcast_config(track)
       }}
    end)
  end

  defp simulcast_config(track) do
    enabled_variants = track.variants -- track.disabled_variants

    %Server.MediaEvent.Track.SimulcastConfig{
      enabled: length(track.variants) > 0,
      enabled_variants: Enum.map(enabled_variants, &to_proto_variant/1),
      disabled_variants: Enum.map(track.disabled_variants, &to_proto_variant/1)
    }
  end

  defp parse_track_id_to_metadata(tracks) do
    Map.new(tracks, fn {track_id, metadata} ->
      {track_id, Jason.decode!(metadata)}
    end)
  end

  defp parse_track_id_to_bitrates(bitrates) do
    Map.new(bitrates, fn {track_id, bitrate} ->
      {track_id, parse_bitrates(bitrate.variant_bitrates)}
    end)
  end

  defp parse_bitrates(bitrates) do
    Map.new(bitrates, fn variant ->
      {from_proto_variant(variant.variant), variant.bitrate}
    end)
  end

  defp parse_ice_servers(ice_servers) do
    Enum.map(ice_servers, fn server ->
      server |> Map.update!(:urls, &update_ice_server_urls/1) |> then(&struct(IceServer, &1))
    end)
  end

  defp update_ice_server_urls(server_urls) do
    case server_urls do
      urls when is_list(urls) -> urls
      url when is_binary(url) -> [url]
    end
  end

  defp to_proto_vad_status(:silence), do: :STATUS_SILENCE
  defp to_proto_vad_status(:speech), do: :STATUS_SPEECH
  defp to_proto_vad_status(_type), do: :STATUS_UNSPECIFIED

  defp to_proto_variant(:low), do: :VARIANT_LOW
  defp to_proto_variant(:medium), do: :VARIANT_MEDIUM
  defp to_proto_variant(_variant), do: :VARIANT_HIGH

  defp from_proto_variant(:VARIANT_LOW), do: :low
  defp from_proto_variant(:VARIANT_MEDIUM), do: :medium
  defp from_proto_variant(_variant), do: :high
end
