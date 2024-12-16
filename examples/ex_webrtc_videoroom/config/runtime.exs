import Config

defmodule ConfigParser do
  def parse_port_range(range) do
    with [str1, str2] <- String.split(range, "-"),
         from when from in 0..65_535 <- String.to_integer(str1),
         to when to in from..65_535//1 and from <= to <- String.to_integer(str2) do
      from..to
    else
      _else ->
        raise("""
        Bad PORT_RANGE enviroment variable value. Expected "from-to", where `from` and `to` \
        are numbers between 0 and 65535 and `from` is not bigger than `to`, got: \
        #{inspect(range)}
        """)
    end
  end
end

config :membrane_rtc_engine_ex_webrtc,
  ice_port_range:
    System.get_env("ICE_PORT_RANGE", "50000-59999")
    |> ConfigParser.parse_port_range(),
  ice_servers: [
    %{urls: "stun:stun.l.google.com:19302"},
    %{urls: "stun:stun.l.google.com:5349"}
  ]

config :membrane_videoroom_demo, VideoRoomWeb.Endpoint, [
  {:url, [host: "localhost"]},
  {:http, [otp_app: :membrane_videoroom_demo, port: System.get_env("SERVER_PORT") || 4000]}
]
