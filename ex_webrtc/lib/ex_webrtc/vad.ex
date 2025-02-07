defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.VAD do
  @moduledoc false

  alias Membrane.RTP.{VadEvent, Utils}
  alias Membrane.RTP.Vad.{AudioLevelQueue, IsSpeakingEstimator}

  @enforce_keys [
    :audio_queue,
    :extension_id,
    :vad_threshold,
    :vad_status,
    :status_changed?,
    :current_timestamp
  ]
  defstruct [
    :audio_queue,
    :extension_id,
    :vad_threshold,
    :vad_status,
    :status_changed?,
    :current_timestamp
  ]

  @type t() :: %__MODULE__{
          audio_queue: AudioLevelQueue.t(),
          extension_id: non_neg_integer(),
          vad_threshold: integer(),
          vad_status: :silence | :speech,
          status_changed?: boolean(),
          current_timestamp: non_neg_integer() | nil
        }

  @timestamp_limit Bitwise.bsl(1, 32)

  @spec new(non_neg_integer(), integer()) :: t()
  def new(extension_id, vad_threshold \\ -32) do
    %__MODULE__{
      audio_queue: AudioLevelQueue.new(),
      extension_id: extension_id,
      vad_threshold: vad_threshold + 127,
      vad_status: :silence,
      status_changed?: false,
      current_timestamp: nil
    }
  end

  @spec update(t(), ExRTP.Packet.t()) :: t()
  def update(state, packet) do
    # NOTE: I don't think that rollover checks are needed but in original implementation there are used
    # so I left them. `https://github.com/membraneframework/membrane_rtp_plugin/blob/v0.30.0/lib/membrane/rtp/vad.ex`
    rollover =
      Utils.from_which_rollover(state.current_timestamp, packet.timestamp, @timestamp_limit)

    cond do
      rollover == :current and packet.timestamp > (state.current_timestamp || 0) ->
        do_update(state, packet)

      rollover == :next ->
        new(state.extension_id, state.vad_threshold - 127)

      true ->
        state
    end
  end

  defp do_update(state, packet) do
    with {:ok, raw_ext} <- ExRTP.Packet.fetch_extension(packet, state.extension_id),
         {:ok, %{level: audio_level}} <- ExRTP.Packet.Extension.AudioLevel.from_raw(raw_ext) do
      decibels = dbov_to_db(audio_level)

      audio_queue = AudioLevelQueue.add(state.audio_queue, decibels)

      vad_status =
        audio_queue
        |> AudioLevelQueue.to_list()
        |> IsSpeakingEstimator.estimate_is_speaking(state.vad_threshold)

      %{
        state
        | audio_queue: audio_queue,
          vad_status: vad_status,
          status_changed?: state.vad_status != vad_status
      }
    else
      _error -> state
    end
  end

  @spec maybe_send_event(t(), term()) :: list()
  def maybe_send_event(state, pad \\ :output)
  def maybe_send_event(%{status_changed?: false}, _pad), do: []

  def maybe_send_event(%{vad_status: vad_status}, pad),
    do: [event: {pad, %VadEvent{vad: vad_status}}]

  defp dbov_to_db(dbov_level), do: 127 - dbov_level
end
