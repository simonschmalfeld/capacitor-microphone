'use strict';

Object.defineProperty(exports, '__esModule', { value: true });

var core = require('@capacitor/core');

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

class MicrophoneWeb extends core.WebPlugin {
    async checkPermissions() {
        throw this.unimplemented('Not implemented on web.');
    }
    async requestPermissions() {
        throw this.unimplemented('Not implemented on web.');
    }
    async startRecording() {
        throw this.unimplemented('Not implemented on web.');
    }
    async stopRecording() {
        throw this.unimplemented('Not implemented on web.');
    }
}

var web = /*#__PURE__*/Object.freeze({
    __proto__: null,
    MicrophoneWeb: MicrophoneWeb
});

exports.Microphone = Microphone;
//# sourceMappingURL=plugin.cjs.js.map
