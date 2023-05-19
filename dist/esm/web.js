import { WebPlugin } from '@capacitor/core';
export class MicrophoneWeb extends WebPlugin {
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
//# sourceMappingURL=web.js.map