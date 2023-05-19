import { WebPlugin } from '@capacitor/core';
import type { MicrophonePlugin, PermissionStatus, AudioRecording } from './definitions';
export declare class MicrophoneWeb extends WebPlugin implements MicrophonePlugin {
    checkPermissions(): Promise<PermissionStatus>;
    requestPermissions(): Promise<PermissionStatus>;
    startRecording(): Promise<void>;
    stopRecording(): Promise<AudioRecording>;
}
