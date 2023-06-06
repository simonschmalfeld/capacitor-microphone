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
    class MicrophoneWeb extends core.WebPlugin {
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

    var web = /*#__PURE__*/Object.freeze({
        __proto__: null,
        MicrophoneWeb: MicrophoneWeb
    });

    exports.Microphone = Microphone;

    Object.defineProperty(exports, '__esModule', { value: true });

    return exports;

}({}, capacitorExports));
//# sourceMappingURL=plugin.js.map
