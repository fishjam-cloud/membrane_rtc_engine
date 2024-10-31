defmodule Fishjam.MediaEvents.Server.MediaEvent.VadNotification.Status do
  @moduledoc false

  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:STATUS_UNSPECIFIED, 0)
  field(:STATUS_SILENCE, 1)
  field(:STATUS_SPEECH, 2)
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.Track do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:track_id, 1, type: :string, json_name: "trackId")
  field(:metadata, 2, type: Fishjam.MediaEvents.Metadata)
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.Endpoint do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:endpoint_id, 1, type: :string, json_name: "endpointId")
  field(:endpoint_type, 2, type: :string, json_name: "endpointType")
  field(:metadata, 3, type: Fishjam.MediaEvents.Metadata)
  field(:tracks, 4, repeated: true, type: Fishjam.MediaEvents.Server.MediaEvent.Track)
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.EndpointUpdated do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:endpoint_id, 1, type: :string, json_name: "endpointId")
  field(:metadata, 2, type: Fishjam.MediaEvents.Metadata)
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.TrackUpdated do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:endpoint_id, 1, type: :string, json_name: "endpointId")
  field(:track_id, 2, type: :string, json_name: "trackId")
  field(:metadata, 3, type: Fishjam.MediaEvents.Metadata)
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.TracksAdded do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:endpoint_id, 1, type: :string, json_name: "endpointId")
  field(:tracks, 2, repeated: true, type: Fishjam.MediaEvents.Server.MediaEvent.Track)
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.TracksRemoved do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:endpoint_id, 1, type: :string, json_name: "endpointId")
  field(:track_ids, 2, repeated: true, type: :string, json_name: "trackIds")
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.EndpointAdded do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:endpoint_id, 1, type: :string, json_name: "endpointId")
  field(:metadata, 2, type: Fishjam.MediaEvents.Metadata)
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.Connected do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:endpoint_id, 1, type: :string, json_name: "endpointId")
  field(:endpoints, 2, repeated: true, type: Fishjam.MediaEvents.Server.MediaEvent.Endpoint)
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.EndpointRemoved do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:endpoint_id, 1, type: :string, json_name: "endpointId")
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.Error do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:message, 1, type: :string)
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.OfferData.TrackTypes do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:audio, 1, type: :int32)
  field(:video, 2, type: :int32)
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.OfferData do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:tracks_types, 1,
    type: Fishjam.MediaEvents.Server.MediaEvent.OfferData.TrackTypes,
    json_name: "tracksTypes"
  )
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.SdpAnswer do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:sdp_answer, 1, type: :string, json_name: "sdpAnswer")

  field(:mid_to_track_id, 2,
    repeated: true,
    type: Fishjam.MediaEvents.MidToTrackId,
    json_name: "midToTrackId"
  )
end

defmodule Fishjam.MediaEvents.Server.MediaEvent.VadNotification do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:track_id, 1, type: :string, json_name: "trackId")

  field(:status, 2,
    type: Fishjam.MediaEvents.Server.MediaEvent.VadNotification.Status,
    enum: true
  )
end

defmodule Fishjam.MediaEvents.Server.MediaEvent do
  @moduledoc false

  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  oneof(:content, 0)

  field(:endpoint_updated, 1,
    type: Fishjam.MediaEvents.Server.MediaEvent.EndpointUpdated,
    json_name: "endpointUpdated",
    oneof: 0
  )

  field(:track_updated, 2,
    type: Fishjam.MediaEvents.Server.MediaEvent.TrackUpdated,
    json_name: "trackUpdated",
    oneof: 0
  )

  field(:tracks_added, 3,
    type: Fishjam.MediaEvents.Server.MediaEvent.TracksAdded,
    json_name: "tracksAdded",
    oneof: 0
  )

  field(:tracks_removed, 4,
    type: Fishjam.MediaEvents.Server.MediaEvent.TracksRemoved,
    json_name: "tracksRemoved",
    oneof: 0
  )

  field(:endpoint_added, 5,
    type: Fishjam.MediaEvents.Server.MediaEvent.EndpointAdded,
    json_name: "endpointAdded",
    oneof: 0
  )

  field(:endpoint_removed, 6,
    type: Fishjam.MediaEvents.Server.MediaEvent.EndpointRemoved,
    json_name: "endpointRemoved",
    oneof: 0
  )

  field(:connected, 7, type: Fishjam.MediaEvents.Server.MediaEvent.Connected, oneof: 0)
  field(:error, 8, type: Fishjam.MediaEvents.Server.MediaEvent.Error, oneof: 0)

  field(:offer_data, 9,
    type: Fishjam.MediaEvents.Server.MediaEvent.OfferData,
    json_name: "offerData",
    oneof: 0
  )

  field(:candidate, 10, type: Fishjam.MediaEvents.Candidate, oneof: 0)

  field(:sdp_answer, 11,
    type: Fishjam.MediaEvents.Server.MediaEvent.SdpAnswer,
    json_name: "sdpAnswer",
    oneof: 0
  )

  field(:vad_notification, 12,
    type: Fishjam.MediaEvents.Server.MediaEvent.VadNotification,
    json_name: "vadNotification",
    oneof: 0
  )
end
