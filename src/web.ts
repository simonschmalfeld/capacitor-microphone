import { WebPlugin } from '@capacitor/core';

import type { MicrophonePlugin, PermissionStatus, AudioRecording } from './definitions';

// We use global variables to make sure that there
// is only one instance of each audio object in the whole app
let audioContextGlobal: AudioContext | null;
let userAudioGlobal: MediaStream | null;
let micAnalyzerNodeGlobal: AnalyserNode | null;
let analyzerInterval: number | undefined;
let recordingEnabled: boolean;
let silenceDetection: boolean;
let mediaRecorder: MediaRecorder;

export class MicrophoneWeb extends WebPlugin implements MicrophonePlugin {

  async checkPermissions(): Promise<PermissionStatus> {
    throw this.unimplemented('Not implemented on web.');
  }

  async requestPermissions(): Promise<PermissionStatus> {
    throw this.unimplemented('Not implemented on web.');
  }

  async enableMicrophone(options: { recordingEnabled: boolean; silenceDetection: boolean; }): Promise<void> {
    recordingEnabled = options.recordingEnabled;
    silenceDetection = options.silenceDetection;
    const sampleRate = recordingEnabled ? 16000 : 8192

    try {
      if (audioContextGlobal) {
        audioContextGlobal.resume();
        return;
      }

      audioContextGlobal = new window.AudioContext({ sampleRate });
      userAudioGlobal = await navigator?.mediaDevices?.getUserMedia({ audio: true });

      if (micAnalyzerNodeGlobal) {
        return;
      }

      let sourceNode = audioContextGlobal.createMediaStreamSource(userAudioGlobal);
      micAnalyzerNodeGlobal = new AnalyserNode(audioContextGlobal, { fftSize: 512 });
      sourceNode.connect(micAnalyzerNodeGlobal);

      analyzerInterval = window.setInterval(() => {
        let rawData = new Float32Array(245);
        micAnalyzerNodeGlobal?.getFloatTimeDomainData(rawData);
        this.notifyListeners('audioDataReceived', { audioData: rawData });

        if (recordingEnabled && silenceDetection && micAnalyzerNodeGlobal) {
          // Compute the max volume level (-Infinity...0)
          const fftBins = new Float32Array(micAnalyzerNodeGlobal.frequencyBinCount); // Number of values manipulated for each sample
          micAnalyzerNodeGlobal.getFloatFrequencyData(fftBins);

          // audioPeakDB varies from -Infinity up to 0
          const audioPeakDB = Math.max(...fftBins);

          if (audioPeakDB < -50) {
            this.notifyListeners('silenceDetected', {});
          } else {
            this.notifyListeners('audioDetected', {});
          }
        }
      }, 50);

      if (recordingEnabled) {
        mediaRecorder = new MediaRecorder(userAudioGlobal, { mimeType: this.getMimeType(), audioBitsPerSecond: 128000 });
        mediaRecorder.ondataavailable = (event) => {
          if (typeof event.data === "undefined") return;
          if (event.data.size === 0) return;

          // Create a blob file from the event data
          const recordedBlob = new Blob([event.data], { type: this.getMimeType() });
          const audioUrl = (window.URL ? URL : webkitURL).createObjectURL(recordedBlob);

          const audioRecording: AudioRecording = {
            dataUrl: audioUrl,
            path: audioUrl,
            webPath: audioUrl,
            duration: recordedBlob.size,
            format: '.wav',
            mimeType: 'audio/pcm',
            blob: recordedBlob
          };

          this.notifyListeners('recordingAvailable', { recording: audioRecording });
        };

        mediaRecorder.start();
      }
    } catch (e) {
      console.error(e);
    }
  }

  async disableMicrophone(): Promise<void> {
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

  getMimeType = () => {
    // Webm is preferred but not supported on iOS
    if (typeof window !== "undefined" && MediaRecorder.isTypeSupported('audio/webm')) {
      return 'audio/webm;codecs=opus';
    }

    return 'audio/mp4';
  }
}
