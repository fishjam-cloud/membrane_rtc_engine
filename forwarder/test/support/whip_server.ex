defmodule Membrane.RTC.Engine.Endpoint.Forwarder.WHIPServer do
  @moduledoc false

  alias ExWebRTC.PeerConnection

  @offer_path "/api/whip"
  @ice_path "api/resource/id"

  @spec init(Keyword.t()) :: {pid(), Bypass.t()}
  def init(opts \\ []) do
    handle_offer = Keyword.get(opts, :offer, true)
    handle_ice = Keyword.get(opts, :ice, true)

    {:ok, pc} = PeerConnection.start_link()
    bypass = Bypass.open()

    if handle_offer,
      do: handle_offer(bypass, pc),
      else: handle_error(bypass, "POST", @offer_path)

    if handle_ice,
      do: handle_ice(bypass, pc),
      else: handle_error(bypass, "PATCH", @ice_path)

    {pc, bypass}
  end

  @spec address(Bypass.t()) :: String.t()
  def address(bypass), do: "http://localhost:#{bypass.port}"

  @spec receive_media?() :: boolean()
  def receive_media?() do
    receive do
      {:ex_webrtc, _pid, {:rtp, _id, _rid, _packet}} -> true
    after
      2_000 -> false
    end
  end

  defp handle_offer(bypass, pc) do
    Bypass.stub(bypass, "POST", @offer_path, fn conn ->
      {:ok, offer_sdp, conn} = Plug.Conn.read_body(conn)
      offer = %ExWebRTC.SessionDescription{type: :offer, sdp: offer_sdp}

      :ok = PeerConnection.set_remote_description(pc, offer)
      {:ok, answer} = PeerConnection.create_answer(pc)
      :ok = PeerConnection.set_local_description(pc, answer)
      :ok = gather_candidates(pc)
      answer = PeerConnection.get_local_description(pc)

      conn
      |> Plug.Conn.put_resp_header("location", @ice_path)
      |> Plug.Conn.put_resp_content_type("application/sdp")
      |> Plug.Conn.resp(201, answer.sdp)
    end)
  end

  defp handle_ice(bypass, pc) do
    Bypass.stub(bypass, "PATCH", @ice_path, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      candidate =
        body
        |> Jason.decode!()
        |> ExWebRTC.ICECandidate.from_json()

      PeerConnection.add_ice_candidate(pc, candidate)

      Plug.Conn.resp(conn, 204, "")
    end)
  end

  defp handle_error(bypass, method, path) do
    Bypass.stub(bypass, method, path, fn conn ->
      Plug.Conn.resp(conn, 500, "")
    end)
  end

  defp gather_candidates(pc) do
    # we either wait for all of the candidates
    # or whatever we were able to gather in one second
    receive do
      {:ex_webrtc, ^pc, {:ice_gathering_state_change, :complete}} -> :ok
    after
      1000 -> :ok
    end
  end
end
