defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.MediaEventJson do
  @moduledoc false

  alias Membrane.RTC.Engine.Endpoint
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.TrackReceiver
  alias Membrane.RTC.Engine.Track

  alias ExWebRTC.{ICECandidate, PeerConnection.Configuration, SessionDescription}

  @type t() :: map()

  @spec connected(Endpoint.id(), [Endpoint.t()], [Configuration.ice_server()]) ::
          t()
  def connected(endpoint_id, other_endpoints, _ice_servers) do
    other_endpoints =
      other_endpoints
      # backward compatibility
      |> Enum.filter(&(&1.id != endpoint_id))
      |> Enum.map(
        &%{
          id: &1.id,
          type: to_type_string(&1.type),
          metadata: &1.metadata,
          # TODO: remove this field (the metadata is already in the tracks)
          trackIdToMetadata: Endpoint.get_active_track_metadata(&1),
          tracks: &1 |> Endpoint.get_active_tracks() |> to_tracks_info()
        }
      )

    %{type: "connected", data: %{id: endpoint_id, otherEndpoints: other_endpoints}}
  end

  @spec endpoint_added(Endpoint.t()) :: t()
  def endpoint_added(%Endpoint{id: id, type: type, metadata: metadata}) do
    %{type: "endpointAdded", data: %{id: id, type: to_type_string(type), metadata: metadata}}
  end

  @spec endpoint_removed(Endpoint.id()) :: t()
  def endpoint_removed(endpoint_id) do
    %{type: "endpointRemoved", data: %{id: endpoint_id}}
  end

  @spec endpoint_updated(Endpoint.t()) :: t()
  def endpoint_updated(%Endpoint{id: id, metadata: metadata}) do
    %{type: "endpointUpdated", data: %{id: id, metadata: metadata}}
  end

  @spec tracks_added(Endpoint.id(), [Track.t()]) :: t()
  def tracks_added(endpoint_id, tracks) do
    track_id_to_metadata = Map.new(tracks, &{&1.id, &1.metadata})

    %{
      type: "tracksAdded",
      data: %{
        endpointId: endpoint_id,
        # TODO: remove this field (the metadata is already in the tracks)
        trackIdToMetadata: track_id_to_metadata,
        tracks: to_tracks_info(tracks)
      }
    }
  end

  @spec tracks_removed(Endpoint.id(), [String.t()]) :: t()
  def tracks_removed(endpoint_id, track_ids) do
    %{type: "tracksRemoved", data: %{endpointId: endpoint_id, trackIds: track_ids}}
  end

  @spec track_updated(Endpoint.id(), String.t(), map()) :: t()
  def track_updated(endpoint_id, track_id, metadata) do
    %{
      type: "trackUpdated",
      data: %{endpointId: endpoint_id, trackId: track_id, metadata: metadata}
    }
  end

  @spec track_variant_disabled(Endpoint.id(), String.t(), String.t()) :: t()
  def track_variant_disabled(endpoint_id, track_id, encoding) do
    %{
      type: "trackEncodingDisabled",
      data: %{endpointId: endpoint_id, trackId: track_id, encoding: encoding}
    }
  end

  @spec track_variant_enabled(Endpoint.id(), String.t(), String.t()) :: t()
  def track_variant_enabled(endpoint_id, track_id, encoding) do
    %{
      type: "trackEncodingEnabled",
      data: %{endpointId: endpoint_id, trackId: track_id, encoding: encoding}
    }
  end

  @spec tracks_priority([String.t()]) :: t()
  def tracks_priority(tracks) do
    %{type: "tracksPriority", data: %{tracks: tracks}}
  end

  @spec encoding_switched(
          Endpoint.id(),
          Track.id(),
          String.t(),
          TrackReceiver.variant_switch_reason()
        ) :: t()
  def encoding_switched(endpoint_id, track_id, encoding, reason) do
    as_custom(%{
      type: "encodingSwitched",
      data: %{endpointId: endpoint_id, trackId: track_id, encoding: encoding, reason: reason}
    })
  end

  @spec sdp_answer(ExWebRTC.SessionDescription.t(), %{String.t() => non_neg_integer()}) :: t()
  def sdp_answer(answer, mid_to_track_id) do
    as_custom(%{
      type: "sdpAnswer",
      data: answer |> SessionDescription.to_json() |> Map.put("midToTrackId", mid_to_track_id)
    })
  end

  @spec offer_data(%{audio: non_neg_integer(), video: non_neg_integer()}) :: t()
  def offer_data(tracks_types) do
    as_custom(%{
      type: "offerData",
      data: %{
        tracksTypes: tracks_types,
        integratedTurnServers: []
      }
    })
  end

  @spec candidate(ICECandidate.t()) :: t()
  def candidate(candidate) do
    as_custom(%{type: "candidate", data: ICECandidate.to_json(candidate)})
  end

  @spec voice_activity(Track.id(), :speech | :silence) :: t()
  def voice_activity(track_id, vad),
    do:
      as_custom(%{
        type: "vadNotification",
        data: %{
          trackId: track_id,
          status: vad
        }
      })

  @spec bandwidth_estimation(non_neg_integer()) :: t()
  def bandwidth_estimation(estimation),
    do:
      as_custom(%{
        type: "bandwidthEstimation",
        data: %{
          estimation: estimation
        }
      })

  @spec to_action(t()) :: [notify_parent: {:forward_to_parent, {:media_event, binary()}}]
  def to_action(event) do
    [notify_parent: {:forward_to_parent, {:media_event, Jason.encode!(event)}}]
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, :invalid_media_event}
  def decode(event_json) do
    with {:ok, event} <- Jason.decode(event_json), do: do_decode(event)
  end

  defp do_decode(%{"type" => "connect", "data" => %{"metadata" => metadata}}),
    do: {:ok, %{type: :connect, data: %{metadata: metadata}}}

  defp do_decode(%{"type" => "disconnect"}), do: {:ok, %{type: :disconnect}}

  defp do_decode(%{"type" => "custom", "data" => data}) do
    with {:ok, event} <- decode_custom_media_event(data), do: {:ok, %{type: :custom, data: event}}
  end

  defp do_decode(%{"type" => "updateEndpointMetadata", "data" => %{"metadata" => metadata}}),
    do: {:ok, %{type: :update_endpoint_metadata, data: %{metadata: metadata}}}

  defp do_decode(%{
         "type" => "updateTrackMetadata",
         "data" => %{"trackId" => track_id, "trackMetadata" => metadata}
       }),
       do:
         {:ok,
          %{type: :update_track_metadata, data: %{track_id: track_id, track_metadata: metadata}}}

  defp do_decode(%{
         "type" => "disableTrackEncoding",
         "data" => %{"trackId" => track_id, "encoding" => rid}
       }) do
    variant = Endpoint.ExWebRTC.to_track_variant(rid)
    {:ok, %{type: :disable_track_variant, data: %{track_id: track_id, variant: variant}}}
  end

  defp do_decode(%{
         "type" => "enableTrackEncoding",
         "data" => %{"trackId" => track_id, "encoding" => rid}
       }) do
    variant = Endpoint.ExWebRTC.to_track_variant(rid)
    {:ok, %{type: :enable_track_variant, data: %{track_id: track_id, variant: variant}}}
  end

  defp do_decode(%{
         "type" => "muteTrack",
         "data" => %{"trackId" => track_id}
       }),
       do: {:ok, %{type: :mute_track, data: %{track_id: track_id}}}

  defp do_decode(%{
         "type" => "unmuteTrack",
         "data" => %{"trackId" => track_id}
       }),
       do: {:ok, %{type: :unmute_track, data: %{track_id: track_id}}}

  defp do_decode(_event), do: {:error, :invalid_media_event}

  defp decode_custom_media_event(%{"type" => "renegotiateTracks"}) do
    {:ok, %{type: :renegotiate_tracks}}
  end

  defp decode_custom_media_event(%{"type" => "prioritizeTrack"} = event) do
    case event do
      %{"type" => "prioritizeTrack", "data" => %{"trackId" => track_id}} ->
        {:ok, %{type: :prioritize_track, data: %{track_id: track_id}}}

      _other ->
        {:error, :invalid_media_event}
    end
  end

  defp decode_custom_media_event(%{"type" => "unprioritizeTrack"} = event) do
    case event do
      %{"type" => "unprioritizeTrack", "data" => %{"trackId" => track_id}} ->
        {:ok, %{type: :unprioritize_track, data: %{track_id: track_id}}}

      _other ->
        {:error, :invalid_media_event}
    end
  end

  defp decode_custom_media_event(%{"type" => "preferedVideoSizes"} = event) do
    case event do
      %{
        "type" => "preferedVideoSizes",
        "data" => %{
          "bigScreens" => big_screens,
          "mediumScreens" => medium_screens,
          "smallScreens" => small_screens,
          "allSameSize" => same_size?
        }
      } ->
        {:ok,
         %{
           type: :prefered_video_sizes,
           data: %{
             big_screens: big_screens,
             medium_screens: medium_screens,
             small_screens: small_screens,
             same_size?: same_size?
           }
         }}

      _other ->
        {:error, :invalid_media_event}
    end
  end

  defp decode_custom_media_event(%{"type" => "candidate"} = event) do
    case event do
      %{
        "type" => "candidate",
        "data" => candidate
      } ->
        {:ok,
         %{
           type: :candidate,
           data: ICECandidate.from_json(candidate)
         }}

      _other ->
        {:error, :invalid_media_event}
    end
  end

  defp decode_custom_media_event(%{"type" => "trackVariantBitrates"} = event) do
    case event do
      %{
        "type" => "trackVariantBitrates",
        "data" => %{
          "trackId" => track_id,
          "variantBitrates" => variant_bitrates
        }
      } ->
        {:ok,
         %{
           type: :track_bitrate,
           data: %{
             track_id: track_id,
             bitrates: to_track_variants(variant_bitrates)
           }
         }}

      _other ->
        {:error, :invalid_media_event}
    end
  end

  defp decode_custom_media_event(%{"type" => "sdpOffer"} = event) do
    case event do
      %{
        "type" => "sdpOffer",
        "data" =>
          %{
            "sdpOffer" => offer,
            "trackIdToTrackMetadata" => track_id_to_track_metadata,
            "midToTrackId" => mid_to_track_id
          } = data
      } ->
        # use default bitrates in VariantSelector if not present
        default_bitrates =
          Map.new(track_id_to_track_metadata, fn {id, _metadata} -> {id, %{}} end)

        track_id_to_track_bitrate =
          data
          |> Map.get("trackIdToTrackBitrates", default_bitrates)
          |> Map.new(fn {id, bitrate} -> {id, to_track_variants(bitrate)} end)

        {:ok,
         %{
           type: :sdp_offer,
           data: %{
             sdp_offer: SessionDescription.from_json(offer),
             track_id_to_track_metadata: track_id_to_track_metadata,
             track_id_to_track_bitrates: track_id_to_track_bitrate,
             mid_to_track_id: mid_to_track_id
           }
         }}

      _other ->
        {:error, :invalid_media_event}
    end
  end

  defp decode_custom_media_event(%{"type" => "setTargetTrackVariant"} = event) do
    case event do
      %{
        "type" => "setTargetTrackVariant",
        "data" => %{
          "trackId" => track_id,
          "variant" => rid
        }
      } ->
        {:ok,
         %{
           type: :set_target_track_variant,
           data: %{track_id: track_id, variant: rid_to_track_variant(rid)}
         }}

      _other ->
        {:error, :invalid_media_event}
    end
  end

  defp decode_custom_media_event(_event), do: {:error, :invalid_media_event}

  defp as_custom(msg) do
    %{type: "custom", data: msg}
  end

  defp rid_to_track_variant(rid) when rid in ["h", nil], do: :high
  defp rid_to_track_variant("m"), do: :medium
  defp rid_to_track_variant("l"), do: :low

  defp to_track_variants(bitrate) when is_map(bitrate) do
    Map.new(bitrate, fn {rid, bitrate} -> {Endpoint.ExWebRTC.to_track_variant(rid), bitrate} end)
  end

  defp to_track_variants(bitrate) when is_number(bitrate), do: %{high: bitrate}

  defp to_type_string(type), do: Module.split(type) |> List.last() |> String.downcase()

  defp to_tracks_info(tracks) do
    Map.new(
      tracks,
      &{&1.id, %{metadata: &1.metadata, simulcastConfig: get_simulcast_config(&1)}}
    )
  end

  defp get_simulcast_config(track) do
    %{
      enabled: track.variants != [:high],
      activeEncodings: Enum.map(track.variants, &Endpoint.ExWebRTC.to_rid/1),
      disabledEncodings: Enum.map(track.disabled_variants, &Endpoint.ExWebRTC.to_rid/1)
    }
  end
end
