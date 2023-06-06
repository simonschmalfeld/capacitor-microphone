import { WebPlugin } from '@capacitor/core';

import type { MicrophonePlugin, PermissionStatus, AudioRecording } from './definitions';

// We use global variables to make sure that there
// is only one instance of each audio object in the whole app
let audioContextGlobal: AudioContext | null;
let userAudioGlobal: MediaStream | null;
let micAnalyzerNodeGlobal: AnalyserNode | null;
let analyzerInterval: number | undefined;

export class MicrophoneWeb extends WebPlugin implements MicrophonePlugin {

  async checkPermissions(): Promise<PermissionStatus> {
    throw this.unimplemented('Not implemented on web.');
  }

  async requestPermissions(): Promise<PermissionStatus> {
    throw this.unimplemented('Not implemented on web.');
  }

  async enableMicrophone(): Promise<void> {
    try {
      if (audioContextGlobal) {
        audioContextGlobal.resume();
        return;
      }

      audioContextGlobal = new window.AudioContext({ sampleRate: 8192 });
      userAudioGlobal = await navigator?.mediaDevices?.getUserMedia({ audio: true });
      
      if (!micAnalyzerNodeGlobal) {
        let sourceNode = audioContextGlobal.createMediaStreamSource(userAudioGlobal);
        micAnalyzerNodeGlobal = new AnalyserNode(audioContextGlobal, { fftSize: 512 });
        sourceNode.connect(micAnalyzerNodeGlobal);

        analyzerInterval = window.setInterval(() => {
          let rawData = new Float32Array(245);
          micAnalyzerNodeGlobal?.getFloatTimeDomainData(rawData);
          this.notifyListeners('audioDataReceived', { audioData: rawData });
        }, 50);
      }
    } catch (e) {
      console.error(e);
    }
  }

  async disableMicrophone(): Promise<AudioRecording | void> {
    try {
      const tracks = userAudioGlobal?.getTracks();
      tracks?.forEach((track) => track.stop());
      userAudioGlobal = null;

      micAnalyzerNodeGlobal?.disconnect();
      micAnalyzerNodeGlobal = null;
      window.clearInterval(analyzerInterval);
      analyzerInterval = undefined;

      await audioContextGlobal?.close();
      audioContextGlobal = null;
    } catch (e) {
      console.error(e);
    }
  }
}
