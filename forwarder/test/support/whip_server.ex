defmodule Membrane.RTC.Engine.Endpoint.Forwarder.WHIPServer do
  @moduledoc false

  alias ExWebRTC.PeerConnection

  @offer_path "api/whip/"
  @ice_path "api/resource/"

  @spec init(String.t(), Keyword.t()) :: {pid(), Bypass.t()}
  def init(stream_id, opts \\ []) do
    handle_offer = Keyword.get(opts, :offer, true)
    handle_ice = Keyword.get(opts, :ice, true)

    {:ok, pc} = PeerConnection.start()
    Process.monitor(pc)

    bypass = Bypass.open()

    if handle_offer,
      do: handle_offer(bypass, pc, stream_id),
      else: handle_error(bypass, "POST", @offer_path, stream_id)

    if handle_ice,
      do: handle_ice(bypass, pc, stream_id),
      else: handle_error(bypass, "PATCH", @ice_path, stream_id)

    {pc, bypass}
  end

  @spec address(Bypass.t(), String.t()) :: String.t()
  def address(bypass, stream_id), do: "http://localhost:#{bypass.port}/#{stream_id}"

  @spec whip_endpoint(String.t()) :: String.t()
  def whip_endpoint(stream_id), do: @offer_path <> stream_id

  @spec receive_media?() :: boolean()
  def receive_media?() do
    receive do
      {:ex_webrtc, _pid, {:rtp, _id, _rid, _packet}} -> true
    after
      2_000 -> false
    end
  end

  @spec await_disconnect() :: :ok | :error
  def await_disconnect() do
    receive do
      {:ex_webrtc, _pc, {:connection_state_change, :failed}} -> :ok
    after
      20_000 -> :error
    end
  end

  @spec close(Bypass.t()) :: :ok
  def close(bypass) do
    Bypass.down(bypass)
  end

  defp handle_offer(bypass, pc, stream_id) do
    Bypass.stub(bypass, "POST", @offer_path <> stream_id, fn conn ->
      {:ok, offer_sdp, conn} = Plug.Conn.read_body(conn)
      offer = %ExWebRTC.SessionDescription{type: :offer, sdp: offer_sdp}

      :ok = PeerConnection.set_remote_description(pc, offer)
      {:ok, answer} = PeerConnection.create_answer(pc)
      :ok = PeerConnection.set_local_description(pc, answer)
      :ok = gather_candidates(pc)
      answer = PeerConnection.get_local_description(pc)

      conn
      |> Plug.Conn.put_resp_header("location", @ice_path <> stream_id)
      |> Plug.Conn.put_resp_content_type("application/sdp")
      |> Plug.Conn.resp(201, answer.sdp)
    end)
  end

  defp handle_ice(bypass, pc, stream_id) do
    Bypass.stub(bypass, "PATCH", @ice_path <> stream_id, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      candidate =
        body
        |> Jason.decode!()
        |> ExWebRTC.ICECandidate.from_json()

      PeerConnection.add_ice_candidate(pc, candidate)

      Plug.Conn.resp(conn, 204, "")
    end)
  end

  defp handle_error(bypass, method, path, stream_id) do
    Bypass.stub(bypass, method, path <> stream_id, fn conn ->
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
