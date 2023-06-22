import { WebPlugin } from '@capacitor/core';
// We use global variables to make sure that there
// is only one instance of each audio object in the whole app
let audioContextGlobal;
let userAudioGlobal;
let micAnalyzerNodeGlobal;
let analyzerInterval;
let recordingEnabled;
let silenceDetection;
let mediaRecorder;
export class MicrophoneWeb extends WebPlugin {
    async checkPermissions() {
        throw this.unimplemented('Not implemented on web.');
    }
    async requestPermissions() {
        throw this.unimplemented('Not implemented on web.');
    }
    async enableMicrophone(options) {
        var _a;
        recordingEnabled = options.recordingEnabled;
        silenceDetection = options.silenceDetection;
        const sampleRate = recordingEnabled ? 16000 : 8192;
        try {
            if (audioContextGlobal) {
                audioContextGlobal.resume();
                return;
            }
            audioContextGlobal = new window.AudioContext({ sampleRate });
            userAudioGlobal = await ((_a = navigator === null || navigator === void 0 ? void 0 : navigator.mediaDevices) === null || _a === void 0 ? void 0 : _a.getUserMedia({ audio: true }));
            if (micAnalyzerNodeGlobal) {
                return;
            }
            const sourceNode = audioContextGlobal.createMediaStreamSource(userAudioGlobal);
            micAnalyzerNodeGlobal = new AnalyserNode(audioContextGlobal, { fftSize: 256 });
            sourceNode.connect(micAnalyzerNodeGlobal);
            analyzerInterval = window.setInterval(() => {
                const audioData = new Float32Array(245);
                micAnalyzerNodeGlobal === null || micAnalyzerNodeGlobal === void 0 ? void 0 : micAnalyzerNodeGlobal.getFloatTimeDomainData(audioData);
                const frequencyData = new Uint8Array(256);
                micAnalyzerNodeGlobal === null || micAnalyzerNodeGlobal === void 0 ? void 0 : micAnalyzerNodeGlobal.getByteFrequencyData(frequencyData);
                this.notifyListeners('audioDataReceived', { audioData, frequencyData });
                if (recordingEnabled && silenceDetection && micAnalyzerNodeGlobal) {
                    // Compute the max volume level (-Infinity...0)
                    const fftBins = new Float32Array(micAnalyzerNodeGlobal.frequencyBinCount); // Number of values manipulated for each sample
                    micAnalyzerNodeGlobal.getFloatFrequencyData(fftBins);
                    // audioPeakDB varies from -Infinity up to 0
                    const audioPeakDB = Math.max(...fftBins);
                    if (audioPeakDB < -50) {
                        this.notifyListeners('silenceDetected', {});
                    }
                    else {
                        this.notifyListeners('audioDetected', {});
                    }
                }
            }, 10);
            if (recordingEnabled) {
                mediaRecorder = new MediaRecorder(userAudioGlobal, { mimeType: this.getMimeType(), audioBitsPerSecond: 128000 });
                mediaRecorder.ondataavailable = (event) => {
                    if (typeof event.data === "undefined")
                        return;
                    if (event.data.size === 0)
                        return;
                    // Create a blob file from the event data
                    const recordedBlob = new Blob([event.data], { type: this.getMimeType() });
                    const audioUrl = (window.URL ? URL : webkitURL).createObjectURL(recordedBlob);
                    const audioRecording = {
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
        }
        catch (e) {
            console.error(e);
        }
    }
    async disableMicrophone() {
        try {
            if (recordingEnabled) {
                mediaRecorder.stop();
            }
            const tracks = userAudioGlobal === null || userAudioGlobal === void 0 ? void 0 : userAudioGlobal.getTracks();
            tracks === null || tracks === void 0 ? void 0 : tracks.forEach((track) => track.stop());
            userAudioGlobal = null;
            micAnalyzerNodeGlobal === null || micAnalyzerNodeGlobal === void 0 ? void 0 : micAnalyzerNodeGlobal.disconnect();
            micAnalyzerNodeGlobal = null;
            window.clearInterval(analyzerInterval);
            analyzerInterval = undefined;
            await (audioContextGlobal === null || audioContextGlobal === void 0 ? void 0 : audioContextGlobal.close());
            audioContextGlobal = null;
        }
        catch (e) {
            console.error(e);
        }
    }
    requestData() {
        mediaRecorder.requestData();
    }
    getAudioContext() {
        return Promise.resolve(audioContextGlobal);
    }
    getMimeType() {
        // Webm is preferred but not supported on iOS
        if (typeof window !== "undefined" && MediaRecorder.isTypeSupported('audio/webm')) {
            return 'audio/webm;codecs=opus';
        }
        return 'audio/mp4';
    }
}
//# sourceMappingURL=web.js.map