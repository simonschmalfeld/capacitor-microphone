import Capacitor
import AVFoundation
import AudioToolbox

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(MicrophonePlugin)
public class MicrophonePlugin: CAPPlugin {
    let audioEngine = AVAudioEngine()
    let bufferSize: AVAudioFrameCount = 245
    private var implementation: Microphone? = nil
    private var audioQueue: AudioQueueRef?
    private var audioBuffer: AudioQueueBufferRef?
    private var analysisBuffer: Array<Any> = []
    private var timer: Timer?
    private var silenceDetected: UInt8 = 0
    private var file: AVAudioFile?
    private var audioFilePath: URL!
    private var record: Bool = false
    
    public override func load() {
        setupAudioEngine()
    }
        
    func setupAudioEngine() {
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord)
            let ioBufferDuration = 128.0 / 48000.0
            try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(ioBufferDuration)
        } catch {
            assertionFailure("AVAudioSession setup error: \(error)")
        }
        
        let inputNode = audioEngine.inputNode
        let mixerNode = audioEngine.mainMixerNode
        let k44mixer = AVAudioMixerNode()
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let outputFormat = inputNode.outputFormat(forBus: 0)

        let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 8192.0, channels: 1, interleaved: true)
        let formatConverter = AVAudioConverter(from: inputFormat, to: recordingFormat!)
        
        let k44format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: true)
        
        audioEngine.attach(k44mixer)
        audioEngine.connect(inputNode, to: k44mixer, format: inputFormat)
        audioEngine.connect(k44mixer, to: mixerNode, format: k44format)
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: outputFormat) { (buffer, _) in
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
        
        audioFilePath = getDirectoryToSaveAudioFile().appendingPathComponent("\(UUID().uuidString).wav")
        try! file = AVAudioFile(forWriting: audioFilePath, settings: k44mixer.outputFormat(forBus: 0).settings)

        k44mixer.installTap(onBus: 0, bufferSize: 1024, format: k44mixer.outputFormat(forBus: 0)) { (buffer, time) in
            if (self.record == false) {
                return
            }
            
            do {
                print("writing")
                try self.file?.write(from: buffer)
            } catch {
                print(NSString(string: "Write failed: \(error)"));
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
        let silenceDetection = call.getBool("silenceDetection")
        let recordingEnabled = call.getBool("recordingEnabled")
        record = recordingEnabled == true
        
        try! audioEngine.start()
        call.resolve(["status": StatusMessageTypes.microphoneEnabled.rawValue])
        
//
//        if(!isAudioRecordingPermissionGranted()) {
//            call.reject(StatusMessageTypes.microphonePermissionNotGranted.rawValue)
//            return
//        }
//
//        if(implementation != nil) {
//            call.reject(StatusMessageTypes.recordingInProgress.rawValue)
//            return
//        }
//
//        implementation = Microphone()
//        if(implementation == nil) {
//            call.reject(StatusMessageTypes.cannotRecordOnThisPhone.rawValue)
//            return
//        }
//
//        let successfullyStartedRecording = implementation!.startRecording()
//
//        if successfullyStartedRecording == false {
//            call.reject(StatusMessageTypes.cannotRecordOnThisPhone.rawValue)
//            return
//        }
//
//        if (silenceDetection == true) {
//            DispatchQueue.main.sync {
//                self.timer?.invalidate()
//                self.timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(detectSilence), userInfo: nil, repeats: true)
//            }
//        }
    }
    
    @objc func disableMicrophone(_ call: CAPPluginCall) {
        if(audioEngine.isRunning == false) {
            call.reject(StatusMessageTypes.noRecordingInProgress.rawValue)
            return
        }

//        DispatchQueue.main.sync {
//            if (self.timer != nil) {
//                self.timer?.invalidate()
//                self.timer = nil
//            }
//        }
        
        audioEngine.stop()
        file = nil
        
        let webURL = bridge?.portablePath(fromLocalURL: audioFilePath)
        let base64String = readFileAsBase64(audioFilePath)
        
        let audioRecording = AudioRecording(
            base64String: base64String,
            dataUrl: (base64String != nil) ? ("data:audio/pcm;base64," + base64String!) : nil,
            path: audioFilePath?.absoluteString,
            webPath: webURL?.path,
            duration: getAudioFileDuration(audioFilePath),
            format: ".wav",
            mimeType: "audio/pcm"
        )

        if audioRecording.base64String == nil || audioRecording.duration < 0 {
            call.reject(StatusMessageTypes.failedToFetchRecording.rawValue)
        } else {
            call.resolve(audioRecording.toDictionary())
        }
    }
    
    @objc func detectSilence() {
//        let decibels = implementation!.getMeters()
//
//        if (decibels < -35) {
//            silenceDetected += 1
//        } else {
//            silenceDetected = 0
//        }
//
//        if (silenceDetected > 3) {
//            timer?.invalidate()
//            silenceDetected = 0
//            self.notifyListeners("silenceDetected", data: [:])
//        }
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
    
    private func getDirectoryToSaveAudioFile() -> URL {
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
}
