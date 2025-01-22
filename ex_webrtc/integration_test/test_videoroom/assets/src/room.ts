import {
  Endpoint,
  TrackContext,
  TrackKind,
  SimulcastConfig,
  SimulcastBandwidthLimit,
  TrackBandwidthLimit,
  SerializedMediaEvent,
  Variant,
} from "@fishjam-cloud/webrtc-client";

import { WebRTCEndpoint } from "@fishjam-cloud/webrtc-client";

// @ts-ignore
import { Push, Socket } from "phoenix";
import {
  addVideoElement,
  removeVideoElement,
  setErrorMessage,
  attachStream,
} from "./room_ui";

export const LOCAL_ENDPOINT_ID = "local-endpoint";

export type EndpointMetadata = string;
export type TrackMetadata = string;

const SIMULCAST_CONFIG: SimulcastConfig = {
  enabled: true,
  enabledVariants: [
    Variant.VARIANT_LOW,
    Variant.VARIANT_MEDIUM,
    Variant.VARIANT_HIGH,
  ],
  disabledVariants: [],
};

const SIMULCAST_BANDWIDTH: SimulcastBandwidthLimit = new Map([
  [Variant.VARIANT_LOW, 150],
  [Variant.VARIANT_MEDIUM, 500],
  [Variant.VARIANT_HIGH, 1500],
]);

export class Room {
  public endpointId: string | undefined;
  private endpoints: Endpoint[] = [];
  private displayName: string;
  private localStream: MediaStream | undefined;
  public webrtc: WebRTCEndpoint;
  private constraints: MediaStreamConstraints;

  public streams: { [key: string]: MediaStream };
  private removedTracks: string[];

  private socket;
  private webrtcSocketRefs: string[] = [];
  private webrtcChannel;

  public lastPeerMetadata: EndpointMetadata | undefined;
  public lastTrackMetadata: TrackMetadata | undefined;

  private updateMetadataOnStart: boolean;

  private simulcastEnabled: boolean;
  private simulcastConfig: SimulcastConfig | undefined;
  private bandwidth: TrackBandwidthLimit | undefined;

  constructor(
    contraints: MediaStreamConstraints,
    updateMetadata: boolean,
    simulcast: boolean
  ) {
    this.constraints = contraints;
    this.updateMetadataOnStart = updateMetadata;
    this.simulcastEnabled = simulcast;
    this.simulcastConfig = this.simulcastEnabled ? SIMULCAST_CONFIG : undefined;
    this.bandwidth = this.simulcastEnabled ? SIMULCAST_BANDWIDTH : undefined;
    this.socket = new Socket("/socket");
    this.socket.connect();
    this.displayName = "someone";
    this.webrtcChannel = this.socket.channel("room");

    this.webrtcChannel.onError(() => {
      this.socketOff();
      window.location.reload();
    });
    this.webrtcChannel.onClose(() => {
      this.socketOff();
      window.location.reload();
    });

    this.webrtcSocketRefs.push(this.socket.onError(this.leave));
    this.webrtcSocketRefs.push(this.socket.onClose(this.leave));

    this.webrtc = new WebRTCEndpoint();
    this.streams = {};
    this.removedTracks = [];

    const pathParams = new URLSearchParams(window.location.search);
    const stubBitrates = pathParams.get("stubBitrates") || false;

    if (stubBitrates) {
      // Stub trackIdToBitrates to simulate empty trackIdToTrackBitrates map
      this.webrtc.local.getTrackIdToTrackBitrates = () => ({});
    }

    this.webrtc.on("sendMediaEvent", (mediaEvent: SerializedMediaEvent) => {
      this.webrtcChannel.push("mediaEvent", mediaEvent.buffer);
    });

    this.webrtc.on("connectionError", (e) => setErrorMessage(e.message));

    this.webrtc.on(
      "connected",
      async (endpointId: string, otherEndpoints: Endpoint[]) => {
        this.endpointId = endpointId;
        this.endpoints = otherEndpoints.filter(
          (endpoint) => endpoint.id != this.endpointId
        );
        this.endpoints.forEach((endpoint) => {
          const displayName =
            (endpoint.metadata as EndpointMetadata) || "undefined";
          addVideoElement(endpoint.id, displayName, false);
        });
        console.log(this.endpoints);
        this.updateParticipantsList();

        for (const track of this.localStream!.getTracks()) {
          const trackId = await this.webrtc.addTrack(
            track,
            { peer: this.displayName, kind: track.kind },
            this.simulcastConfig,
            this.bandwidth
          );
          if (this.updateMetadataOnStart) {
            this.webrtc.updateTrackMetadata(trackId, "updatedMetadataOnStart");
          }
        }
      }
    );
    this.webrtc.on("connectionError", () => {
      throw `Endpoint denied.`;
    });

    this.webrtc.on("trackReady", (ctx: TrackContext) => {
      this.streams[ctx.stream!.id] = ctx.stream!;

      console.log("trackReady", ctx.trackId, ctx.track!.kind, ctx.stream!.id);
      attachStream(ctx.stream!, ctx.endpoint.id);
    });

    this.webrtc.on("trackRemoved", (ctx) => {
      this.removedTracks.push(ctx.track!.id);

      console.log("trackRemoved", ctx.track!.id, ctx.track!.kind);

      if (
        ctx.stream
          ?.getTracks()!
          .every((track) => this.removedTracks.includes(track.id))
      )
        delete this.streams[ctx.stream!.id];
    });

    this.webrtc.on("endpointAdded", (endpoint: Endpoint) => {
      // Ignore endpointAdded notifications received before `connected` event
      if (this.endpointId && endpoint.id != this.endpointId) {
        this.endpoints.push(endpoint);
        this.updateParticipantsList();
        addVideoElement(
          endpoint.id,
          endpoint.metadata as EndpointMetadata,
          false
        );
      }
    });

    this.webrtc.on("endpointRemoved", (endpoint: Endpoint) => {
      this.endpoints = this.endpoints.filter((e) => e.id !== endpoint.id);
      removeVideoElement(endpoint.id);
      this.updateParticipantsList();
    });

    this.webrtcChannel.on("mediaEvent", (event: ArrayBuffer) => {
      const mediaEvent = new Uint8Array(event);

      this.webrtc.receiveMediaEvent(mediaEvent);
    });

    this.webrtc.on("endpointUpdated", (endpoint) => {
      this.lastPeerMetadata = endpoint.metadata as EndpointMetadata;
    });

    this.webrtc.on("trackUpdated", (ctx) => {
      this.lastTrackMetadata = ctx.metadata as TrackMetadata;
    });
  }

  public join = async () => {
    try {
      await this.init();
      this.webrtc.connect({ displayName: this.displayName });
    } catch (error) {
      console.error("Error while joining to the room:", error);
    }
  };

  public updateMetadata = (metadata: EndpointMetadata) => {
    this.webrtc.updateEndpointMetadata({ peer: metadata });
  };

  public updateTrackMetadata = (metadata: TrackMetadata) => {
    const tracks = this.webrtc.getLocalEndpoint().tracks;
    const trackId = tracks.keys().next().value!;
    this.webrtc.updateTrackMetadata(trackId, metadata);
  };

  public selectPeerSimulcastVariant = (rid: Variant) => {
    const remoteTracks = Object.entries(this.webrtc.getRemoteTracks());

    const videoTracks = remoteTracks.filter((track) => {
      const [_, trackContext] = track;
      return trackContext.track?.kind === "video";
    });

    videoTracks.forEach((track) => {
      const [trackId, _] = track;
      this.webrtc.setTargetTrackEncoding(trackId, rid);
    });
  };

  public disableSimulcastVariant = (rid: Variant) => {
    const [trackId, _] = Array.from(
      this.webrtc.getLocalEndpoint().tracks
    ).filter((track) => {
      const [_, trackContext] = track;
      return trackContext.track?.kind === "video";
    })[0];
    this.webrtc.disableTrackEncoding(trackId, rid);
  };

  public enableSimulcastVariant = (rid: Variant) => {
    const [trackId, _] = Array.from(
      this.webrtc.getLocalEndpoint().tracks
    ).filter((track) => {
      const [_, trackContext] = track;
      return trackContext.track?.kind === "video";
    })[0];

    this.webrtc.enableTrackEncoding(trackId, rid);
  };

  public getEndpointRemoteTrackCtx = (
    endpointId: string,
    kind: TrackKind
  ): TrackContext => {
    const tracksCtxs = Array.from(Object.values(this.webrtc.getRemoteTracks()));
    console.log(
      this.webrtc.getRemoteTracks(),
      tracksCtxs,
      endpointId,
      this.endpointId,
      kind
    );

    const trackCtx = tracksCtxs.find(
      (trackCtx) =>
        trackCtx.endpoint.id === endpointId && trackCtx.track?.kind === kind
    );
    return trackCtx!;
  };

  private init = async () => {
    if (this.constraints.audio != false || this.constraints.video != false) {
      try {
        this.localStream = await navigator.mediaDevices.getUserMedia(
          this.constraints
        );
      } catch (error) {
        console.error(error);
        setErrorMessage(
          "Failed to setup video room, make sure to grant camera and microphone permissions"
        );
        throw "error";
      }

      addVideoElement(LOCAL_ENDPOINT_ID, "Me", true);
      attachStream(this.localStream!, LOCAL_ENDPOINT_ID);
    }

    await this.phoenixChannelPushResult(this.webrtcChannel.join());
  };

  public leave = () => {
    this.webrtc.disconnect();
    this.webrtcChannel.leave();
    this.socketOff();
  };

  private socketOff = () => {
    this.socket.off(this.webrtcSocketRefs);
    while (this.webrtcSocketRefs.length > 0) {
      this.webrtcSocketRefs.pop();
    }
  };

  private updateParticipantsList = (): void => {
    const participantsNames = this.endpoints.map(
      (e) => e.metadata as EndpointMetadata
    );

    if (this.displayName) {
      participantsNames.push(this.displayName);
    }
  };

  private phoenixChannelPushResult = async (push: Push): Promise<any> => {
    return new Promise((resolve, reject) => {
      push
        .receive("ok", (response: any) => resolve(response))
        .receive("error", (response: any) => reject(response));
    });
  };
}
