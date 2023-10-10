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
        audioContextGlobal.close();
      }

      audioContextGlobal = new window.AudioContext({ sampleRate });
      userAudioGlobal = await navigator?.mediaDevices?.getUserMedia({ audio: true });

      if (micAnalyzerNodeGlobal) {
        return;
      }

      const sourceNode = audioContextGlobal.createMediaStreamSource(userAudioGlobal);
      micAnalyzerNodeGlobal = new AnalyserNode(audioContextGlobal, { fftSize: 256 });
      sourceNode.connect(micAnalyzerNodeGlobal);

      analyzerInterval = window.setInterval(() => {
        const audioData = new Float32Array(245);
        micAnalyzerNodeGlobal?.getFloatTimeDomainData(audioData);

        const frequencyData = new Uint8Array(256);
        micAnalyzerNodeGlobal?.getByteFrequencyData(frequencyData);

        this.notifyListeners('audioDataReceived', { audioData, frequencyData });

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
      }, 10);

      if (recordingEnabled) {
        mediaRecorder = new MediaRecorder(userAudioGlobal, { mimeType: this.getMimeType(), audioBitsPerSecond: 128000 });
        mediaRecorder.ondataavailable = (e) => this.handleDataAvailable(e);
        mediaRecorder.start();
      }
    } catch (e) {
      console.error(e);
    }
  }

  async disableMicrophone(): Promise<void> {
    try {
      if (recordingEnabled) {
        mediaRecorder.stop();
      }
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

  requestData(): void {
    if (!userAudioGlobal) {
      throw 'No audio context';
    }
    
    mediaRecorder.stop();
    mediaRecorder = new MediaRecorder(userAudioGlobal, { mimeType: this.getMimeType(), audioBitsPerSecond: 128000 });
    mediaRecorder.ondataavailable = (e) => this.handleDataAvailable(e);
    mediaRecorder.start();
  }

  getAudioContext(): Promise<AudioContext | null> {
    return Promise.resolve(audioContextGlobal);
  }

  getMimeType(): string {
    // Webm is preferred but not supported on iOS
    if (typeof window !== "undefined" && MediaRecorder.isTypeSupported('audio/webm')) {
      return 'audio/webm;codecs=opus';
    }

    return 'audio/mp4';
  }

  handleDataAvailable(event: BlobEvent): void {
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
  }
}
