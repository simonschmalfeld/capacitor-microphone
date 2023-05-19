import { registerPlugin } from '@capacitor/core';
const Microphone = registerPlugin('Microphone', {
    web: () => import('./web').then(m => new m.MicrophoneWeb()),
});
export * from './definitions';
export { Microphone };
//# sourceMappingURL=index.js.map