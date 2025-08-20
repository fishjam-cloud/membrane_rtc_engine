defmodule Membrane.RTC.Engine.Endpoint.Agent.TrackUtils do
  @moduledoc false

  alias Fishjam.AgentRequest.AddTrack
  alias Fishjam.AgentRequest.AddTrack.CodecParameters
  alias Fishjam.Notifications

  alias Membrane.RTC.Engine.Endpoint
  alias Membrane.RTC.Engine.Track

  @pcm_sample_rates [16_000, 24_000]

  @spec create_track(AddTrack.t(), Endpoint.id()) :: Track.t()
  def create_track(
        %AddTrack{track: %Notifications.Track{} = track, codec_params: params},
        endpoint_id
      ) do
    track = from_proto_track(track)
    codec_params = from_proto_codec_params(params)

    Track.new(
      track.type,
      Track.stream_id(),
      endpoint_id,
      :opus,
      codec_params.sample_rate,
      %{},
      id: track.id,
      metadata: Jason.decode!(track.metadata),
      variants: [:high]
    )
  end

  @spec validate_codec_params(CodecParameters.t()) ::
          {:ok, map()} | {:error, :invalid_codec_params}
  def validate_codec_params(%CodecParameters{} = codec_parameters) do
    params = from_proto_codec_params(codec_parameters)

    cond do
      params.channels != 1 -> {:error, :invalid_codec_params}
      params.encoding == :opus -> {:ok, params}
      params.encoding == :pcm16 && params.sample_rate in @pcm_sample_rates -> {:ok, params}
      true -> {:error, :invalid_codec_params}
    end
  end

  @spec to_proto_track(Track.t()) :: Notifications.Track.t()
  def to_proto_track(track) do
    %Notifications.Track{
      id: track.id,
      type: to_proto_track_type(track.type),
      metadata: Jason.encode!(track.metadata)
    }
  end

  defp from_proto_codec_params(%CodecParameters{} = codec_parameters) do
    codec_parameters
    |> Map.from_struct()
    |> Map.update!(:encoding, &from_proto_track_encoding/1)
  end

  defp from_proto_track(%Notifications.Track{} = track) do
    track
    |> Map.from_struct()
    |> Map.update!(:type, &from_proto_track_type/1)
  end

  defp from_proto_track_encoding(:TRACK_ENCODING_OPUS), do: :opus
  defp from_proto_track_encoding(:TRACK_ENCODING_PCM16), do: :pcm16
  defp from_proto_track_encoding(_encoding), do: nil

  defp from_proto_track_type(:TRACK_TYPE_VIDEO), do: :video
  defp from_proto_track_type(:TRACK_TYPE_AUDIO), do: :audio
  defp from_proto_track_type(_type), do: nil

  defp to_proto_track_type(:video), do: :TRACK_TYPE_VIDEO
  defp to_proto_track_type(:audio), do: :TRACK_TYPE_AUDIO
end
