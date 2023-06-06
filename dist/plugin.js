var capacitorMicrophone = (function (exports, core) {
    'use strict';

    exports.MicrophonePermissionStateValue = void 0;
    (function (MicrophonePermissionStateValue) {
        MicrophonePermissionStateValue["prompt"] = "prompt";
        MicrophonePermissionStateValue["promptWithRationale"] = "prompt-with-rationale";
        MicrophonePermissionStateValue["granted"] = "granted";
        MicrophonePermissionStateValue["denied"] = "denied";
        MicrophonePermissionStateValue["limited"] = "limited";
    })(exports.MicrophonePermissionStateValue || (exports.MicrophonePermissionStateValue = {}));

    const Microphone = core.registerPlugin('Microphone', {
        web: () => Promise.resolve().then(function () { return web; }).then(m => new m.MicrophoneWeb()),
    });

    // We use global variables to make sure that there
    // is only one instance of each audio object in the whole app
    let audioContextGlobal;
    let userAudioGlobal;
    let micAnalyzerNodeGlobal;
    let analyzerInterval;
    let recordingEnabled;
    // let silenceDetection: boolean;
    let mediaRecorder;
    class MicrophoneWeb extends core.WebPlugin {
        constructor() {
            super(...arguments);
            this.getMimeType = () => {
                // Webm is preferred but not supported on iOS
                if (typeof window !== "undefined" && MediaRecorder.isTypeSupported('audio/webm')) {
                    return 'audio/webm;codecs=opus';
                }
                return 'audio/mp4';
            };
        }
        async checkPermissions() {
            throw this.unimplemented('Not implemented on web.');
        }
        async requestPermissions() {
            throw this.unimplemented('Not implemented on web.');
        }
        async enableMicrophone(options) {
            var _a;
            recordingEnabled = options.recordingEnabled;
            // silenceDetection = options.silenceDetection;
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

    var web = /*#__PURE__*/Object.freeze({
        __proto__: null,
        MicrophoneWeb: MicrophoneWeb
    });

    exports.Microphone = Microphone;

    Object.defineProperty(exports, '__esModule', { value: true });

    return exports;

}({}, capacitorExports));
//# sourceMappingURL=plugin.js.map
