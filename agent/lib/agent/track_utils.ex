defmodule Membrane.RTC.Engine.Endpoint.Agent.TrackUtils do
  @moduledoc false

  alias Fishjam.AgentRequest.AddTrack
  alias Fishjam.AgentRequest.AddTrack.CodecParameters
  alias Fishjam.Notifications

  alias Membrane.RTC.Engine.Track

  @valid_audio_parameters [
    %{
      encoding: :OPUS,
      channels: 1
    },
    %{
      encoding: :PCM16,
      sample_rate: 16_000,
      channels: 1
    },
    %{
      encoding: :PCM16,
      sample_rate: 24_000,
      channels: 1
    }
  ]

  def create_track(%AddTrack{track: %Notifications.Track{} = track, codec_params: params}, endpoint_id) do
    track = from_proto_track(track)
    codec_params = from_proto_codec_params(params)

    Track.new(
      track.type,
      Track.stream_id(),
      endpoint_id,
      codec_params.encoding,
      codec_params.sample_rate,
      %{},
      id: track.id,
      metadata: track.metadata,
      variants: [:high]
    )
  end

  defp from_proto_track(%Notifications.Track{} = track) do
    track
    |> Map.from_struct()
    |> Map.update!(:type, &from_proto_track_type/1)
  end

  defp from_proto_codec_params(%CodecParameters{} = codec_parameters) do
    codec_parameters
    |> Map.from_struct()
    |> Map.update!(:encoding, &from_proto_track_encoding/1)
  end

  defp from_proto_track_encoding(:TRACK_ENCODING_OPUS), do: :opus
  defp from_proto_track_encoding(:TRACK_ENCODING_PCM16), do: :s16le
  defp from_proto_track_encoding(_encoding), do: nil

  defp from_proto_track_type(:TRACK_TYPE_VIDEO), do: :video
  defp from_proto_track_type(:TRACK_TYPE_AUDIO), do: :audio
  defp from_proto_track_type(_type), do: nil
end
