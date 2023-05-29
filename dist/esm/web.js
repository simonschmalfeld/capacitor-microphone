import { WebPlugin } from '@capacitor/core';
export class MicrophoneWeb extends WebPlugin {
    async checkPermissions() {
        throw this.unimplemented('Not implemented on web.');
    }
    async requestPermissions() {
        throw this.unimplemented('Not implemented on web.');
    }
    // async startRecording(): Promise<void> {
    //   throw this.unimplemented('Not implemented on web.');
    // }
    // async stopRecording(): Promise<AudioRecording> {
    //   throw this.unimplemented('Not implemented on web.');
    // }
    async enableMicrophone() {
        throw this.unimplemented('Not implemented on web.');
    }
    async disableMicrophone() {
        throw this.unimplemented('Not implemented on web.');
    }
}
//# sourceMappingURL=web.js.map