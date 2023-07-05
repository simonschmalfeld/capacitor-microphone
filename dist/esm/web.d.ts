/// <reference types="dom-mediacapture-record" />
import { WebPlugin } from '@capacitor/core';
import type { MicrophonePlugin, PermissionStatus } from './definitions';
export declare class MicrophoneWeb extends WebPlugin implements MicrophonePlugin {
    checkPermissions(): Promise<PermissionStatus>;
    requestPermissions(): Promise<PermissionStatus>;
    enableMicrophone(options: {
        recordingEnabled: boolean;
        silenceDetection: boolean;
    }): Promise<void>;
    disableMicrophone(): Promise<void>;
    requestData(): void;
    getAudioContext(): Promise<AudioContext | null>;
    getMimeType(): string;
    handleDataAvailable(event: BlobEvent): void;
}
