defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.PeerConnectionHandler.InboundTrack do
  @moduledoc false

  alias ExSDP.Attribute.Extmap

  alias Membrane.RTC.Engine.Endpoint.ExWebRTC, as: EndpointExWebRTC
  alias Membrane.RTC.Engine.Track

  @type encoding :: :OPUS | :VP8 | :H264
  @type variant_state :: :new | :ready | :linked
  @type variants :: %{EndpointExWebRTC.track_variant() => variant_state()}

  @enforce_keys [:track_id, :simulcast?, :vad, :variants, :encoding]

  defstruct @enforce_keys

  @type t() :: %__MODULE__{
          track_id: Track.id(),
          simulcast?: boolean(),
          vad: EndpointExWebRTC.VAD.t() | nil,
          variants: variants(),
          encoding: :h264 | :vp8
        }

  @spec init(Track.id(), ExWebRTC.MediaStreamTrack.t(), encoding(), Extmap.t()) :: t()
  def init(track_id, track, encoding, vad_extension) do
    vad =
      case track.kind do
        :audio -> EndpointExWebRTC.VAD.new(vad_extension.id)
        :video -> nil
      end

    variants =
      if is_nil(track.rids),
        do: %{high: :new},
        else: Map.new(track.rids, &{EndpointExWebRTC.to_track_variant(&1), :new})

    %__MODULE__{
      track_id: track_id,
      simulcast?: not is_nil(track.rids),
      vad: vad,
      variants: variants,
      encoding: encoding
    }
  end

  @spec maybe_update_vad(t(), Membrane.Pad.ref(), ExRTP.Packet.t()) ::
          {[Membrane.Element.Action.t()], t()}
  def maybe_update_vad(%{vad: nil} = track, _pad, _packet) do
    {[], track}
  end

  def maybe_update_vad(%{vad: vad} = track, pad, packet) do
    vad = EndpointExWebRTC.VAD.update(vad, packet)
    actions = EndpointExWebRTC.VAD.maybe_send_event(vad, pad)

    {actions, Map.put(track, :vad, vad)}
  end

  @spec update_variant_state(t(), EndpointExWebRTC.track_variant(), variant_state()) :: t()
  def update_variant_state(state, rid, variant_state) do
    update_in(state.variants, &Map.put(&1, rid, variant_state))
  end
end
