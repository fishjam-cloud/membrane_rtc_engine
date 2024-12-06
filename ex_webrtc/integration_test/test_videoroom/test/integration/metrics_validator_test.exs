defmodule TestVideoroom.MetricsValidatorTest do
  use ExUnit.Case

  alias TestVideoroom.MetricsValidator

  @valid_report %{
    :"inbound-rtp.frames" => 711,
    :"inbound-rtp.keyframes" => 6,
    {:endpoint_id, "880b05c2-26ec-4570-bdb0-b3135cfb0f51"} => %{
      :"endpoint.metadata" => nil,
      {:candidate_id, 14_026_748_491_453_184_096_451_935_712} => %{
        "remote_candidate.port": 57451,
        "remote_candidate.candidate_type": :host,
        "remote_candidate.address": {64769, 20937, 50361, 10743, 6191, 60062, 61488, 28880},
        "remote_candidate.protocol": :udp
      },
      {:candidate_id, 32_868_965_248_888_745_976_920_688_227} => %{
        "remote_candidate.port": 52079,
        "remote_candidate.candidate_type": :host,
        "remote_candidate.address": {192, 168, 83, 211},
        "remote_candidate.protocol": :udp
      },
      {:candidate_id, 45_401_189_091_481_423_807_557_611_453} => %{
        "remote_candidate.port": 64199,
        "remote_candidate.candidate_type": :host,
        "remote_candidate.address": {64868, 26973, 45153, 21239, 4306, 27448, 49169, 9579},
        "remote_candidate.protocol": :udp
      },
      {:track_id, 17_624_400_963_682_007_360_158_917_538} => %{
        "outbound-rtp.bytes_sent_total": 18123,
        "outbound-rtp.packets_sent_total": 869,
        "outbound-rtp.bytes_sent": 38763,
        "outbound-rtp.packets_sent": 861,
        "outbound-rtp.nack_count": 0,
        "outbound-rtp.pli_count": 0,
        "outbound-rtp.markers_sent": 1,
        "outbound-rtp.retransmitted_packets_sent": 0,
        "outbound-rtp.retransmitted_bytes_sent": 0
      },
      {:track_id, 19_661_563_003_324_897_918_202_467_222} => %{
        "inbound-rtp.bytes_received_total": 32470,
        "inbound-rtp.packets_received_total": 869,
        "inbound-rtp.bytes_received": 49754,
        "inbound-rtp.packets_received": 861,
        "inbound-rtp.nack_count": 0,
        "inbound-rtp.pli_count": 0,
        "inbound-rtp.markers_received": 1,
        "inbound-rtp.codec": "opus"
      },
      {:track_id, 40_536_105_556_528_381_230_985_426_570} => %{
        "inbound-rtp.bytes_received_total": 627_866,
        "inbound-rtp.packets_received_total": 711,
        "inbound-rtp.bytes_received": 630_870,
        "inbound-rtp.packets_received": 700,
        "inbound-rtp.nack_count": 0,
        "inbound-rtp.pli_count": 0,
        "inbound-rtp.markers_received": 354,
        "inbound-rtp.codec": "VP8"
      },
      {:track_id, 45_142_545_509_899_998_558_361_891_913} => %{
        "outbound-rtp.bytes_sent_total": 613_269,
        "outbound-rtp.packets_sent_total": 700,
        "outbound-rtp.bytes_sent": 621_353,
        "outbound-rtp.packets_sent": 691,
        "outbound-rtp.nack_count": 0,
        "outbound-rtp.pli_count": 0,
        "outbound-rtp.markers_sent": 342,
        "outbound-rtp.retransmitted_packets_sent": 0,
        "outbound-rtp.retransmitted_bytes_sent": 0
      },
      {:track_id, "880b05c2-26ec-4570-bdb0-b3135cfb0f51:975ea58f-d4f9-4883-bf0b-d65c0518f427:h"} =>
        %{
          "track.metadata": %{"kind" => "audio", "peer" => "someone"}
        },
      {:track_id, "880b05c2-26ec-4570-bdb0-b3135cfb0f51:da2a5f8b-ce90-4a56-960f-6a9b516842f2:h"} =>
        %{
          "track.metadata": %{"kind" => "video", "peer" => "someone"}
        }
    },
    {:endpoint_id, "9f360310-3c39-4c06-8e56-4b03c219203f"} => %{
      :"endpoint.metadata" => nil,
      {:candidate_id, 4_316_758_042_763_144_371_620_902_461} => %{
        "remote_candidate.port": 61619,
        "remote_candidate.candidate_type": :host,
        "remote_candidate.address": {64769, 20937, 50361, 10743, 6191, 60062, 61488, 28880},
        "remote_candidate.protocol": :udp
      },
      {:candidate_id, 12_838_722_509_836_369_313_583_058_448} => %{
        "remote_candidate.port": 57870,
        "remote_candidate.candidate_type": :host,
        "remote_candidate.address": {64868, 26973, 45153, 21239, 4306, 27448, 49169, 9579},
        "remote_candidate.protocol": :udp
      },
      {:candidate_id, 42_097_866_262_092_454_953_939_447_754} => %{
        "remote_candidate.port": 63088,
        "remote_candidate.candidate_type": :host,
        "remote_candidate.address": {192, 168, 83, 211},
        "remote_candidate.protocol": :udp
      },
      {:track_id, 14_421_130_449_273_850_722_417_999_534} => %{
        "inbound-rtp.bytes_received_total": 18123,
        "inbound-rtp.packets_received_total": 869,
        "inbound-rtp.bytes_received": 35471,
        "inbound-rtp.packets_received": 861,
        "inbound-rtp.nack_count": 0,
        "inbound-rtp.pli_count": 0,
        "inbound-rtp.markers_received": 1,
        "inbound-rtp.codec": "opus"
      },
      {:track_id, 21_544_248_585_878_222_070_106_624_216} => %{
        "inbound-rtp.bytes_received_total": 629_237,
        "inbound-rtp.packets_received_total": 718,
        "inbound-rtp.bytes_received": 635_165,
        "inbound-rtp.packets_received": 709,
        "inbound-rtp.nack_count": 0,
        "inbound-rtp.pli_count": 0,
        "inbound-rtp.markers_received": 360,
        "inbound-rtp.codec": "VP8"
      },
      {:track_id, 32_580_941_273_413_257_887_365_770_913} => %{
        "outbound-rtp.bytes_sent_total": 615_802,
        "outbound-rtp.packets_sent_total": 699,
        "outbound-rtp.bytes_sent": 621_210,
        "outbound-rtp.packets_sent": 688,
        "outbound-rtp.nack_count": 0,
        "outbound-rtp.pli_count": 0,
        "outbound-rtp.markers_sent": 342,
        "outbound-rtp.retransmitted_packets_sent": 0,
        "outbound-rtp.retransmitted_bytes_sent": 0
      },
      {:track_id, 55_846_976_219_512_124_544_222_914_403} => %{
        "outbound-rtp.bytes_sent_total": 32470,
        "outbound-rtp.packets_sent_total": 869,
        "outbound-rtp.bytes_sent": 53110,
        "outbound-rtp.packets_sent": 861,
        "outbound-rtp.nack_count": 0,
        "outbound-rtp.pli_count": 0,
        "outbound-rtp.markers_sent": 1,
        "outbound-rtp.retransmitted_packets_sent": 0,
        "outbound-rtp.retransmitted_bytes_sent": 0
      },
      {:track_id, "9f360310-3c39-4c06-8e56-4b03c219203f:c4239011-91d8-42ca-9f9b-21362a3e4d04:h"} =>
        %{
          "track.metadata": %{"kind" => "video", "peer" => "someone"}
        },
      {:track_id, "9f360310-3c39-4c06-8e56-4b03c219203f:c8948440-c09c-4ef5-bbbb-60323b83c6e0:h"} =>
        %{
          "track.metadata": %{"kind" => "audio", "peer" => "someone"}
        }
    },
    {:track_id, "880b05c2-26ec-4570-bdb0-b3135cfb0f51:975ea58f-d4f9-4883-bf0b-d65c0518f427"} => %{
      "outbound-rtp.variant": :high,
      "outbound-rtp.variant-reason": :set_bandwidth_allocation
    },
    {:track_id, "880b05c2-26ec-4570-bdb0-b3135cfb0f51:da2a5f8b-ce90-4a56-960f-6a9b516842f2"} => %{
      "outbound-rtp.variant": :high,
      "outbound-rtp.variant-reason": :set_bandwidth_allocation
    },
    {:track_id, "9f360310-3c39-4c06-8e56-4b03c219203f:c4239011-91d8-42ca-9f9b-21362a3e4d04"} => %{
      "outbound-rtp.variant": :high,
      "outbound-rtp.variant-reason": :set_bandwidth_allocation
    },
    {:track_id, "9f360310-3c39-4c06-8e56-4b03c219203f:c8948440-c09c-4ef5-bbbb-60323b83c6e0"} => %{
      "outbound-rtp.variant": :high,
      "outbound-rtp.variant-reason": :set_bandwidth_allocation
    }
  }

  test "Validates correct report" do
    assert :ok == MetricsValidator.validate_report(@valid_report)
  end

  test "Invalidates incorrect reports" do
    report =
      Map.update!(
        @valid_report,
        {:endpoint_id, "9f360310-3c39-4c06-8e56-4b03c219203f"},
        &Map.delete(&1, :"endpoint.metadata")
      )

    assert {:error, _reason} = MetricsValidator.validate_report(report)

    report =
      Map.update!(
        @valid_report,
        {:endpoint_id, "9f360310-3c39-4c06-8e56-4b03c219203f"},
        &Map.delete(&1, {:track_id, 14_421_130_449_273_850_722_417_999_534})
      )

    assert {:error, _reason} = MetricsValidator.validate_report(report)

    report =
      update_in(
        @valid_report,
        [
          {:endpoint_id, "9f360310-3c39-4c06-8e56-4b03c219203f"},
          {:track_id, 21_544_248_585_878_222_070_106_624_216}
        ],
        &Map.delete(&1, :"inbound-rtp.bytes_received_total")
      )

    assert {:error, _reason} = MetricsValidator.validate_report(report)
  end
end
