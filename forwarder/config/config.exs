import Config

config :membrane_rtc_engine_ex_webrtc,
  ice_port_range: nil,
  ice_servers: [
    %{urls: "stun:stun.l.google.com:19302"},
    %{urls: "stun:stun.l.google.com:5349"}
  ]

import_config "#{config_env()}.exs"
