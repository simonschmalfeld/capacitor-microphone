import Capacitor
import AVFoundation
import AudioToolbox

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(MicrophonePlugin)
public class MicrophonePlugin: CAPPlugin {
    private var implementation: Microphone? = nil
    private var audioQueue: AudioQueueRef?
    private var audioBuffer: AudioQueueBufferRef?
    private var listenerHandle: Any?
    private var analysisBuffer: Array<Any> = []
    let audioEngine = AVAudioEngine()
    let bufferSize: AVAudioFrameCount = 245
    
    public override func load() {
        setupAudioEngine()
    }
    
    func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try! audioSession.setCategory(.record, mode: .default)
        try! audioSession.setActive(true)
    }
        
    func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 8192.0, channels: 1, interleaved: true)
        let formatConverter = AVAudioConverter(from: inputFormat, to: recordingFormat!)
        
        listenerHandle = inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { (buffer, _) in
            
            let pcmBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat!, frameCapacity: AVAudioFrameCount(recordingFormat!.sampleRate))
            var error: NSError? = nil

            let inputBlock: AVAudioConverterInputBlock = {inNumPackets, outStatus in
                outStatus.pointee = AVAudioConverterInputStatus.haveData
                return buffer
            }

            formatConverter?.convert(to: pcmBuffer!, error: &error, withInputFrom: inputBlock)

            if error != nil {
                print(error!.localizedDescription)
            }

            else if let floatChannelData = pcmBuffer!.floatChannelData {
                let channelData = stride(from: 0, to: Int(pcmBuffer!.frameLength),
                                         by: pcmBuffer!.stride).map{ floatChannelData.pointee[$0] }
                self.analysisBuffer = Array(channelData.prefix(numericCast(self.bufferSize)))
                self.notifyListeners("audioDataReceived", data: ["audioData": self.analysisBuffer])
            }
        }

        audioEngine.prepare()
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        var result: [String: Any] = [:]
        for permission in MicrophonePermissionType.allCases {
            let state: String
            switch permission {
            case .microphone:
                state = AVCaptureDevice.authorizationStatus(for: .audio).authorizationState
            }
            result[permission.rawValue] = state
        }
        call.resolve(result)
    }
    
    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        // TODO: (CHECK) We are not even sending permission list (Do we need it ?)
        // get the list of desired types, if passed
        let typeList = call.getArray("permissions", String.self)?.compactMap({ (type) -> MicrophonePermissionType? in
            return MicrophonePermissionType(rawValue: type)
        }) ?? []
        // otherwise check everything
        let permissions: [MicrophonePermissionType] = (typeList.count > 0) ? typeList : MicrophonePermissionType.allCases
        // request the permissions
        let group = DispatchGroup()
        for permission in permissions {
            switch permission {
            case .microphone:
                group.enter()
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    group.leave()
                }
            }
        }
        group.notify(queue: DispatchQueue.main) { [weak self] in
            self?.checkPermissions(call)
        }
    }
    
    @objc func enableMicrophone(_ call: CAPPluginCall) {
        try! audioEngine.start()
        call.resolve(["status": StatusMessageTypes.microphoneEnabled.rawValue])
    }
    
    @objc func disableMicrophone(_ call: CAPPluginCall) {
//        if let handle = listenerHandle as? AVAudioNodeTapBlock {
//            let inputNode = audioEngine.inputNode
//            inputNode.removeTap(onBus: 0)
//            listenerHandle = nil
//       }
        audioEngine.stop()
        call.resolve(["status": StatusMessageTypes.microphoneDisabled.rawValue])
    }
    
    @objc func startRecording(_ call: CAPPluginCall) {
        if(!isAudioRecordingPermissionGranted()) {
            call.reject(StatusMessageTypes.microphonePermissionNotGranted.rawValue)
            return
        }
        
        if(implementation != nil) {
            call.reject(StatusMessageTypes.recordingInProgress.rawValue)
            return
        }
        
        implementation = Microphone()
        if(implementation == nil) {
            call.reject(StatusMessageTypes.cannotRecordOnThisPhone.rawValue)
            return
        }
        
        let successfullyStartedRecording = implementation!.startRecording()
        if successfullyStartedRecording == false {
            call.reject(StatusMessageTypes.cannotRecordOnThisPhone.rawValue)
        } else {
            call.resolve(["status": StatusMessageTypes.recordingStared.rawValue])
        }
    }

    @objc func stopRecording(_ call: CAPPluginCall) {
        if(implementation == nil) {
            call.reject(StatusMessageTypes.noRecordingInProgress.rawValue)
            return
        }
        
        implementation?.stopRecording()
        
        let audioFileUrl = implementation?.getOutputFile()
        if(audioFileUrl == nil) {
            implementation = nil
            call.reject(StatusMessageTypes.failedToFetchRecording.rawValue)
            return
        }
        
        let webURL = bridge?.portablePath(fromLocalURL: audioFileUrl)
        let base64String = readFileAsBase64(audioFileUrl)
        
        let audioRecording = AudioRecording(
            base64String: base64String,
            dataUrl: (base64String != nil) ? ("data:audio/pcm;base64," + base64String!) : nil,
            path: audioFileUrl?.absoluteString,
            webPath: webURL?.path,
            duration: getAudioFileDuration(audioFileUrl),
            format: ".wav",
            mimeType: "audio/pcm"
        )
        implementation = nil
        if audioRecording.base64String == nil || audioRecording.duration < 0 {
            call.reject(StatusMessageTypes.failedToFetchRecording.rawValue)
        } else {
            call.resolve(audioRecording.toDictionary())
        }
    }
    
    private func isAudioRecordingPermissionGranted() -> Bool {
        return AVAudioSession.sharedInstance().recordPermission == AVAudioSession.RecordPermission.granted
    }
    
    private func readFileAsBase64(_ filePath: URL?) -> String? {
        if(filePath == nil) {
            return nil
        }
        
        do {
            let fileData = try Data.init(contentsOf: filePath!)
            let fileStream = fileData.base64EncodedString()
            return fileStream
        } catch {}
        
        return nil
    }
    
    private func getAudioFileDuration(_ filePath: URL?) -> Int {
        if filePath == nil {
            return -1
        }
        return Int(CMTimeGetSeconds(AVURLAsset(url: filePath!).duration) * 1000)
    }
}
