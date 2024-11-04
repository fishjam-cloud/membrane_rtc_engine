defmodule Fishjam.MediaEvents.Peer.MediaEvent.VariantBitrate do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:variant, 1, type: Fishjam.MediaEvents.Variant, enum: true)
  field(:bitrate, 2, type: :int32)
end

defmodule Fishjam.MediaEvents.Peer.MediaEvent.TrackIdToMetadata do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:track_id, 1, type: :string, json_name: "trackId")
  field(:metadata, 2, type: Fishjam.MediaEvents.Metadata)
end

defmodule Fishjam.MediaEvents.Peer.MediaEvent.TrackIdToBitrates do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  oneof(:tracks, 0)

  field(:track_bitrate, 1,
    type: Fishjam.MediaEvents.Peer.MediaEvent.TrackBitrate,
    json_name: "trackBitrate",
    oneof: 0
  )
end

defmodule Fishjam.MediaEvents.Peer.MediaEvent.Connect do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:metadata, 1, type: Fishjam.MediaEvents.Metadata)
end

defmodule Fishjam.MediaEvents.Peer.MediaEvent.Disconnect do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule Fishjam.MediaEvents.Peer.MediaEvent.UpdateEndpointMetadata do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:metadata, 1, type: Fishjam.MediaEvents.Metadata)
end

defmodule Fishjam.MediaEvents.Peer.MediaEvent.UpdateTrackMetadata do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:track_id, 1, type: :string, json_name: "trackId")
  field(:metadata, 2, type: Fishjam.MediaEvents.Metadata)
end

defmodule Fishjam.MediaEvents.Peer.MediaEvent.RenegotiateTracks do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule Fishjam.MediaEvents.Peer.MediaEvent.SdpOffer do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:sdp_offer, 1, type: :string, json_name: "sdpOffer")

  field(:track_id_to_metadata, 2,
    repeated: true,
    type: Fishjam.MediaEvents.Peer.MediaEvent.TrackIdToMetadata,
    json_name: "trackIdToMetadata"
  )

  field(:track_id_to_bitrates, 3,
    repeated: true,
    type: Fishjam.MediaEvents.Peer.MediaEvent.TrackIdToBitrates,
    json_name: "trackIdToBitrates"
  )

  field(:mid_to_track_id, 4,
    repeated: true,
    type: Fishjam.MediaEvents.MidToTrackId,
    json_name: "midToTrackId"
  )
end

defmodule Fishjam.MediaEvents.Peer.MediaEvent.TrackBitrate do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:track_id, 1, type: :string, json_name: "trackId")
  field(:bitrate, 2, type: :int32)
end

defmodule Fishjam.MediaEvents.Peer.MediaEvent do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  oneof(:content, 0)

  field(:connect, 1, type: Fishjam.MediaEvents.Peer.MediaEvent.Connect, oneof: 0)
  field(:disconnect, 2, type: Fishjam.MediaEvents.Peer.MediaEvent.Disconnect, oneof: 0)

  field(:update_endpoint_metadata, 3,
    type: Fishjam.MediaEvents.Peer.MediaEvent.UpdateEndpointMetadata,
    json_name: "updateEndpointMetadata",
    oneof: 0
  )

  field(:update_track_metadata, 4,
    type: Fishjam.MediaEvents.Peer.MediaEvent.UpdateTrackMetadata,
    json_name: "updateTrackMetadata",
    oneof: 0
  )

  field(:renegotiate_tracks, 5,
    type: Fishjam.MediaEvents.Peer.MediaEvent.RenegotiateTracks,
    json_name: "renegotiateTracks",
    oneof: 0
  )

  field(:candidate, 6, type: Fishjam.MediaEvents.Candidate, oneof: 0)

  field(:sdp_offer, 7,
    type: Fishjam.MediaEvents.Peer.MediaEvent.SdpOffer,
    json_name: "sdpOffer",
    oneof: 0
  )

  field(:track_bitrate, 8,
    type: Fishjam.MediaEvents.Peer.MediaEvent.TrackBitrate,
    json_name: "trackBitrate",
    oneof: 0
  )
end
