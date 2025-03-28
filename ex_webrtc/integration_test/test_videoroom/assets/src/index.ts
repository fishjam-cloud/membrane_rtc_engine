import { Variant } from "@fishjam-cloud/webrtc-client";
import { Room } from "./room";
import {
  remoteStreamsStats,
  inboundSimulcastStreamStats,
  outboundSimulcastStreamStats,
} from "./stats";

const data = document.querySelector("div#data") as HTMLElement;

const getButtonsWithPrefix = (types: string[], prefix: string) => {
  return types.map(
    (type) =>
      document.querySelector(`button#${prefix}-${type}`) as HTMLButtonElement,
  );
};

const startButtons = getButtonsWithPrefix(
  ["simulcast", "all", "all-update", "mic-only", "camera-only", "none"],
  "start",
);

const [videoOffButton, videoOnButton] = getButtonsWithPrefix(
  ["off", "on"],
  "video",
);

const simulcastButtons = getButtonsWithPrefix(
  [
    "local-low-variant",
    "local-medium-variant",
    "local-high-variant",
    "peer-low-variant",
    "peer-medium-variant",
    "peer-high-variant",
  ],
  "simulcast",
);

const simulcastStatsButtons: HTMLButtonElement[] = getButtonsWithPrefix(
  ["inbound-stats", "outbound-stats"],
  "simulcast",
);

const metadataButtons = getButtonsWithPrefix(
  ["update-peer", "update-track", "peer", "track"],
  "metadata",
);

const [
  startSimulcastButton,
  startAllButton,
  startAllUpdateButton,
  startMicOnlyButton,
  startCameraOnlyButton,
  startNoneButton,
] = startButtons;
const [
  localLowVariantButton,
  localMediumVariantButton,
  localHighVariantButton,
  peerLowVariantButton,
  peerMediumVariantButton,
  peerHighVariantButton,
] = simulcastButtons;

const [inboundSimulcastStatsButton, outboundSimulcastStatsButton] =
  simulcastStatsButtons;

const [
  updatePeerMetadataButton,
  updateTrackMetadataButton,
  peerMetadataButton,
  trackMetadataButton,
] = metadataButtons;

const stopButton = document.querySelector("button#stop") as HTMLButtonElement;
const statsButton = document.querySelector("button#stats") as HTMLButtonElement;

startButtons.forEach((button) => (button.disabled = false));
metadataButtons.forEach((button) => (button.disabled = false));
simulcastButtons.forEach((button) => (button.disabled = true));
simulcastStatsButtons.forEach((button) => (button.disabled = false));
stopButton.disabled = true;
statsButton.disabled = false;

let room: Room | undefined;

let videoCodec: "vp8" | null = "vp8";

const simulcastPreferences = {
  width: { max: 1280, ideal: 1280, min: 1280 },
  height: { max: 720, ideal: 720, min: 720 },
  frameRate: { max: 30, ideal: 24 },
};

async function start(media: string, simulcast = false) {
  if (room) return;

  const useVideo = ["all", "camera"].some((source) => media.includes(source));
  const useAudio = ["all", "mic"].some((source) => media.includes(source));
  const updateMetadata = media.includes("update");

  if (simulcast) {
    simulcastButtons.map((elem) => (elem.disabled = false));
  }

  const constraints = {
    audio: useAudio,
    video: useVideo && simulcast ? simulcastPreferences : useVideo,
  };

  startButtons.forEach((button) => (button.disabled = true));
  if (stopButton) stopButton.disabled = false;

  room = new Room(constraints, updateMetadata, simulcast, videoCodec);

  await room.join();
}

async function stop() {
  if (!room) return;

  room.leave();

  room = undefined;

  startButtons.forEach((button) => (button.disabled = false));
  stopButton.disabled = true;
}

function putStats(stats: string | object) {
  console.log("putStats", data, JSON.stringify(stats));
  if (data) {
    data.innerHTML = JSON.stringify(stats);

    // update the current accessed version
    data.dataset.version = (parseInt(data.dataset.version!) + 1).toString();
  }
}

async function refreshStats(
  statsFunction: (room: Room) => Promise<string | object>,
) {
  if (!room || !room.webrtc || !room.webrtc.connectionManager?.getConnection) {
    data.innerHTML = `Room error. One of objects doesn't exists: Room ${!room}, WebRTC ${room?.webrtc}, PeerConnection ${room?.webrtc?.connectionManager?.getConnection()}`;
    return;
  }
  const stats = await statsFunction(room);

  putStats(stats);
}

function videoOff() {
  videoCodec = null;
}
function videoOn() {
  videoCodec = "vp8";
}

function toggleSimulcastVariant(button: HTMLButtonElement, rid: Variant) {
  const isEnabled = button.textContent?.startsWith("Disable");
  let text = button.textContent;
  if (isEnabled) {
    room?.disableSimulcastVariant(rid);
    text = text!.replace("Disable", "Enable");
  } else {
    room?.enableSimulcastVariant(rid);
    text = text!.replace("Enable", "Disable");
  }
  button.textContent = text;
}

// setup all button callbacks
startSimulcastButton.onclick = () => start("all", true);
startAllButton.onclick = () => start("all");
startAllUpdateButton.onclick = () => start("all-update");
startMicOnlyButton.onclick = () => start("mic");
startCameraOnlyButton.onclick = () => start("camera");
startNoneButton.onclick = () => start("none");
stopButton.onclick = stop;
videoOffButton.onclick = videoOff;
videoOnButton.onclick = videoOn;
statsButton.onclick = () => {
  refreshStats(remoteStreamsStats);
};
updatePeerMetadataButton.onclick = () => {
  room?.updateMetadata("newMeta");
};
updateTrackMetadataButton.onclick = () => {
  room?.updateTrackMetadata("newTrackMeta");
};
peerMetadataButton.onclick = () => {
  putStats(room?.lastPeerMetadata!);
};
trackMetadataButton.onclick = () => {
  putStats(room?.lastTrackMetadata!);
};
localLowVariantButton.onclick = () => {
  toggleSimulcastVariant(localLowVariantButton, Variant.VARIANT_LOW);
};
localMediumVariantButton.onclick = () => {
  toggleSimulcastVariant(localMediumVariantButton, Variant.VARIANT_MEDIUM);
};
localHighVariantButton.onclick = () => {
  toggleSimulcastVariant(localHighVariantButton, Variant.VARIANT_HIGH);
};
peerLowVariantButton.onclick = () => {
  room?.selectPeerSimulcastVariant(Variant.VARIANT_LOW);
};
peerMediumVariantButton.onclick = () => {
  room?.selectPeerSimulcastVariant(Variant.VARIANT_MEDIUM);
};
peerHighVariantButton.onclick = () => {
  room?.selectPeerSimulcastVariant(Variant.VARIANT_HIGH);
};
inboundSimulcastStatsButton.onclick = () => {
  refreshStats(inboundSimulcastStreamStats);
};
outboundSimulcastStatsButton.onclick = () => {
  refreshStats(outboundSimulcastStreamStats);
};
