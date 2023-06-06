import { WebPlugin } from '@capacitor/core';
// We use global variables to make sure that there
// is only one instance of each audio object in the whole app
let audioContextGlobal;
let userAudioGlobal;
let micAnalyzerNodeGlobal;
let analyzerInterval;
export class MicrophoneWeb extends WebPlugin {
    async checkPermissions() {
        throw this.unimplemented('Not implemented on web.');
    }
    async requestPermissions() {
        throw this.unimplemented('Not implemented on web.');
    }
    async enableMicrophone() {
        var _a;
        try {
            if (audioContextGlobal) {
                audioContextGlobal.resume();
                return;
            }
            audioContextGlobal = new window.AudioContext({ sampleRate: 8192 });
            userAudioGlobal = await ((_a = navigator === null || navigator === void 0 ? void 0 : navigator.mediaDevices) === null || _a === void 0 ? void 0 : _a.getUserMedia({ audio: true }));
            if (!micAnalyzerNodeGlobal) {
                let sourceNode = audioContextGlobal.createMediaStreamSource(userAudioGlobal);
                micAnalyzerNodeGlobal = new AnalyserNode(audioContextGlobal, { fftSize: 512 });
                sourceNode.connect(micAnalyzerNodeGlobal);
                analyzerInterval = window.setInterval(() => {
                    let rawData = new Float32Array(245);
                    micAnalyzerNodeGlobal === null || micAnalyzerNodeGlobal === void 0 ? void 0 : micAnalyzerNodeGlobal.getFloatTimeDomainData(rawData);
                    this.notifyListeners('audioDataReceived', { audioData: rawData });
                }, 50);
            }
        }
        catch (e) {
            console.error(e);
        }
    }
    async disableMicrophone() {
        try {
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
}
//# sourceMappingURL=web.js.map