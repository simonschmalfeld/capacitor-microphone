import Capacitor
import AVFoundation
import AudioToolbox
import Accelerate

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(MicrophonePlugin)
public class MicrophonePlugin: CAPPlugin {
    let audioEngine = AVAudioEngine()
    let bufferSize: AVAudioFrameCount = 245
    let recordingMixer = AVAudioMixerNode()
    let k48format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000.0, channels: 1, interleaved: true)
    let k16format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: true)
    let fftFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 8192.0, channels: 1, interleaved: true)
    private var audioQueue: AudioQueueRef?
    private var audioBuffer: AudioQueueBufferRef?
    private var analysisBuffer: Array<Any> = []
    private var file: AVAudioFile?
    private var audioFilePath: URL!
    private var recordingEnabled: Bool = false
    private var silenceDetection: Bool = false
    private var inputNode: AVAudioInputNode?
    private var mixerNode: AVAudioMixerNode?
    
    public override func load() {
        inputNode = audioEngine.inputNode
        let ioBufferDuration = 128.0 / 48000.0
        
        do {
            try AVAudioSession.sharedInstance().setPreferredSampleRate(16000.0)
            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord)
            try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(ioBufferDuration)
        } catch {
            assertionFailure("AVAudioSession setup error: \(error)")
        }
    }
        
    func setupAudioEngine() {
        if (inputNode == nil) {
            return
        }
        
        let inputFormat = inputNode!.inputFormat(forBus: 0)
        
        audioEngine.attach(recordingMixer)
        audioEngine.connect(inputNode!, to: recordingMixer, format: inputFormat)
        audioEngine.connect(recordingMixer, to: audioEngine.mainMixerNode, format: k16format)
        
        inputNode!.installTap(onBus: 0, bufferSize: bufferSize, format: inputNode!.outputFormat(forBus: 0)) { (buffer, _) in
            let pcmBuffer = self.convertBuffer(buffer: buffer, inputFormat: inputFormat, outputFormat: self.fftFormat!)

            if let floatChannelData = pcmBuffer.floatChannelData {
                let channelData = stride(from: 0, to: Int(pcmBuffer.frameLength),
                                         by: pcmBuffer.stride).map{ floatChannelData.pointee[$0] }
                self.analysisBuffer = Array(channelData.prefix(numericCast(self.bufferSize)))
                self.notifyListeners("audioDataReceived", data: ["audioData": self.analysisBuffer])
            }
        }
        
        if (self.recordingEnabled == true) {
            audioFilePath = getDirectoryToSaveAudioFile().appendingPathComponent("\(UUID().uuidString).wav")
            try! file = AVAudioFile(forWriting: audioFilePath, settings: recordingMixer.outputFormat(forBus: 0).settings)

            recordingMixer.installTap(onBus: 0, bufferSize: 2048, format: recordingMixer.outputFormat(forBus: 0)) { (buffer, time) in
                if (self.silenceDetection == true) {
                    let peak = self.calculatePeakPowerLevel(buffer: buffer)
                    if (peak < 0.05) {
                        self.notifyListeners("silenceDetected", data: [:])
                    } else {
                        self.notifyListeners("audioDetected", data: [:])
                    }
                }

                do {
                    try self.file?.write(from: buffer)
                } catch {
                    print(NSString(string: "Write failed: \(error)"));
                }
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
        if(!isAudioRecordingPermissionGranted()) {
            call.reject(StatusMessageTypes.microphonePermissionNotGranted.rawValue)
            return
        }
        
        recordingEnabled = call.getBool("recordingEnabled") == true
        silenceDetection = call.getBool("silenceDetection") == true
        
        setupAudioEngine()
        try! audioEngine.start()
        
        if audioEngine.isRunning == false {
            call.reject(StatusMessageTypes.cannotRecordOnThisPhone.rawValue)
            return
        }
        
        call.resolve(["status": StatusMessageTypes.microphoneEnabled.rawValue])
    }
    
    @objc func disableMicrophone(_ call: CAPPluginCall) {
        if(audioEngine.isRunning == false || inputNode == nil) {
            call.reject(StatusMessageTypes.noRecordingInProgress.rawValue)
            return
        }
        
        audioEngine.stop()
        inputNode!.removeTap(onBus: 0)
        
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
        
        if (recordingEnabled) {
            recordingMixer.removeTap(onBus: 0)

            if audioRecording.base64String == nil || audioRecording.duration < 0 {
                call.reject(StatusMessageTypes.failedToFetchRecording.rawValue)
            } else {
                self.notifyListeners("recordingAvailable", data: ["recording": audioRecording.toDictionary()])
            }
        }
        
        call.resolve(audioRecording.toDictionary())
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
    
    private func calculatePeakPowerLevel(buffer: AVAudioPCMBuffer) -> Float {
        let channelCount = Int(buffer.format.channelCount)
        let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: channelCount)
        
        var peak: Float = 0.0
        
        for channel in 0..<channelCount {
            let data = channels[channel]
            var channelPeak: Float = 0.0
            vDSP_maxv(data, 1, &channelPeak, vDSP_Length(buffer.frameLength))
            peak = max(peak, channelPeak)
        }
        
        return peak
    }
    
    private func convertBuffer(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) -> AVAudioPCMBuffer {
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(outputFormat.sampleRate))
        var error: NSError? = nil

        let inputBlock: AVAudioConverterInputBlock = {inNumPackets, outStatus in
            outStatus.pointee = AVAudioConverterInputStatus.haveData
            return buffer
        }

        let formatConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
        formatConverter?.convert(to: pcmBuffer!, error: &error, withInputFrom: inputBlock)

        if error != nil {
            print(error!.localizedDescription)
        }

        return pcmBuffer!
    }
}
