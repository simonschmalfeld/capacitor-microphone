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
    private var audioBuffers = [AudioQueueBufferRef?]()
    private var audioFormat = AudioStreamBasicDescription()
    private var microphoneEnabled = false
    
    public override func load() {
        configureAudioFormat()
    }
    
    private func configureAudioFormat() {
        audioFormat.mSampleRate = 8192.0
        audioFormat.mFormatID = kAudioFormatLinearPCM
        audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked
        audioFormat.mBitsPerChannel = 16
        audioFormat.mChannelsPerFrame = 1
        audioFormat.mFramesPerPacket = 1
        audioFormat.mBytesPerFrame = audioFormat.mBitsPerChannel / 8 * audioFormat.mChannelsPerFrame
        audioFormat.mBytesPerPacket = audioFormat.mBytesPerFrame * audioFormat.mFramesPerPacket
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
        AudioQueueNewInput(&audioFormat, recordingCallback, Unmanaged.passUnretained(self).toOpaque(), nil, nil, 0, &audioQueue)
        
        // Allocate audio queue buffers
        let bufferSize: UInt32 = 4096 // Adjust as per your requirements
        for _ in 0..<3 {
            var bufferRef: AudioQueueBufferRef?
            AudioQueueAllocateBuffer(audioQueue!, bufferSize, &bufferRef)
            
            guard let buffer = bufferRef else { return }
            AudioQueueEnqueueBuffer(audioQueue!, buffer, 0, nil)
            audioBuffers.append(buffer)
        }
        
        // Start the audio queue
        AudioQueueStart(audioQueue!, nil)
        
        call.resolve(["status": StatusMessageTypes.microphoneEnabled.rawValue])
    }
    
    @objc func disableMicrophone(_ call: CAPPluginCall) {
        guard let queue = audioQueue else { return }
        AudioQueueStop(queue, true)
        
        for i in 0..<3 {
            guard let buffer = audioBuffers[i] else { return }
            AudioQueueFreeBuffer(queue, buffer)
        }
        
        AudioQueueDispose(queue, true)
        
        call.resolve(["status": StatusMessageTypes.microphoneDisabled.rawValue])
    }
    
    private let recordingCallback: AudioQueueInputCallback = { (inUserData, inQueue, inBuffer, inStartTime, inNumPackets, inPacketDesc) in
        guard let userData = inUserData else { return }
        
        let audioRecorder = Unmanaged<MicrophonePlugin>.fromOpaque(userData).takeUnretainedValue()
        audioRecorder.processRecordedAudio(buffer: inBuffer)
        
        // Re-enqueue the buffer for continuous recording
        AudioQueueEnqueueBuffer(inQueue, inBuffer, 0, nil)
    }
    
    private func processRecordedAudio(buffer: AudioQueueBufferRef) {
        let samples = buffer.pointee.mAudioData.assumingMemoryBound(to: Int16.self)
        let nsamples = buffer.pointee.mAudioDataByteSize
        let data = NSData(bytes: samples, length: Int(nsamples))
        let str = data.base64EncodedString(options: [.lineLength64Characters])
        self.notifyListeners("audioDataReceived", data: ["audioData": str])
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
            dataUrl: (base64String != nil) ? ("data:audio/aac;base64," + base64String!) : nil,
            path: audioFileUrl?.absoluteString,
            webPath: webURL?.path,
            duration: getAudioFileDuration(audioFileUrl),
            format: ".m4a",
            mimeType: "audio/aac"
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
