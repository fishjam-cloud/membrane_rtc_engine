defmodule Membrane.RTC.FileEndpointTest do
  use ExUnit.Case

  alias ExSDP.Attribute.FMTP

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint
  alias Membrane.RTC.Engine.Message
  alias Membrane.RTC.Engine.Support

  @fixtures_dir "./test/fixtures/"

  setup do
    options = [id: "test_rtc"]

    {:ok, pid} = Engine.start_link(options, [])

    Engine.register(pid, self())

    on_exit(fn -> Engine.terminate(pid) end)

    [rtc_engine: pid]
  end

  @source_endpoint_id "source-endpoint-id"
  @sink_endpoint_id "sink-endpoint-id"
  @out_opus_reference "out_audio.opus"

  describe "File Endpoint test" do
    for mode <- [:autoplay, :manual, :wait_for_first_subscriber] do
      @tag :tmp_dir
      test "test audio with #{mode}", %{rtc_engine: rtc_engine, tmp_dir: tmp_dir} do
        test_endpoint(
          type: :audio,
          rtc_engine: rtc_engine,
          tmp_dir: tmp_dir,
          playback_mode: unquote(mode),
          reference_path: @out_opus_reference
        )
      end

      @tag :tmp_dir
      test "test video with #{mode}", %{rtc_engine: rtc_engine, tmp_dir: tmp_dir} do
        test_endpoint(
          type: :video,
          rtc_engine: rtc_engine,
          tmp_dir: tmp_dir,
          playback_mode: unquote(mode)
        )
      end
    end
  end

  defp test_endpoint(opts) do
    file_name = get_filename(opts[:type])
    file_path = Path.join(@fixtures_dir, file_name)

    reference_path =
      if Keyword.has_key?(opts, :reference_path) do
        Path.join(@fixtures_dir, opts[:reference_path])
      else
        file_path
      end

    output_file = Path.join([opts[:tmp_dir], "out_#{file_name}"])
    rtc_engine = opts[:rtc_engine]

    :ok =
      Engine.add_endpoint(
        rtc_engine,
        %Support.Sink{
          rtc_engine: rtc_engine,
          file_path: output_file
        },
        id: @sink_endpoint_id
      )

    file_endpoint =
      create_file_endpoint(
        opts[:type],
        rtc_engine,
        file_path,
        opts[:playback_mode]
      )

    :ok = Engine.add_endpoint(rtc_engine, file_endpoint, id: @source_endpoint_id)

    assert_receive %Message.EndpointMessage{
      endpoint_id: @source_endpoint_id,
      message: :tracks_added
    }

    assert_receive %Message.EndpointMessage{
      message: :tracks_subscribed
    }

    if opts[:playback_mode] == :manual do
      Endpoint.File.start_sending(rtc_engine, @source_endpoint_id)
    end

    assert_receive %Message.EndpointRemoved{endpoint_id: @source_endpoint_id}, 12_500
    assert_receive %Message.EndpointRemoved{endpoint_id: @sink_endpoint_id}, 12_500
    refute_received %Message.EndpointCrashed{endpoint_id: @sink_endpoint_id}
    refute_received %Message.EndpointCrashed{endpoint_id: @source_endpoint_id}

    assert File.exists?(output_file)

    output = File.read!(output_file)
    reference = File.read!(reference_path)

    output_size = output |> byte_size()
    reference_size = reference |> byte_size()

    if opts[:playback_mode] == :wait_for_first_subscriber do
      assert output_size == reference_size
      assert File.read!(output_file) == File.read!(reference_path)
    else
      assert output_size > 0
      assert output == binary_slice(reference, reference_size - output_size, reference_size)
    end
  end

  defp get_filename(:video), do: "video.h264"
  defp get_filename(:audio), do: "audio.ogg"

  defp create_file_endpoint(
         :video,
         rtc_engine,
         video_file_path,
         playback_mode
       ) do
    video_track_config = %Endpoint.File.TrackConfig{
      type: :video,
      encoding: :H264,
      clock_rate: 90_000,
      fmtp: %FMTP{
        pt: 96
      },
      opts: [framerate: {60, 1}]
    }

    %Endpoint.File{
      rtc_engine: rtc_engine,
      file_path: video_file_path,
      track_config: video_track_config,
      payload_type: 96,
      playback_mode: playback_mode
    }
  end

  defp create_file_endpoint(
         :audio,
         rtc_engine,
         audio_file_path,
         playback_mode
       ) do
    ext = String.split(audio_file_path, ".") |> List.last()

    encoding =
      case ext do
        "aac" -> :AAC
        "ogg" -> :opus
      end

    audio_track_config = %Endpoint.File.TrackConfig{
      type: :audio,
      encoding: encoding,
      clock_rate: 48_000,
      fmtp: %FMTP{
        pt: 108
      }
    }

    %Endpoint.File{
      rtc_engine: rtc_engine,
      file_path: audio_file_path,
      track_config: audio_track_config,
      payload_type: 108,
      playback_mode: playback_mode
    }
  end
end
