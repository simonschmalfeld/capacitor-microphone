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
    getMimeType: () => "audio/webm;codecs=opus" | "audio/mp4";
}
