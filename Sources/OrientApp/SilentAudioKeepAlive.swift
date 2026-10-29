import Foundation
import AVFoundation

/// Keeps the macOS Bluetooth audio transport awake using a zero-amplitude audio source node
/// so connected AirPods stream CMHeadphoneMotionManager packets at maximum polling rate
/// without dropping into low-power idle intervals.
public final class SilentAudioKeepAlive: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    public private(set) var isRunning: Bool = false

    public init() {}

    public func start() {
        guard !isRunning else { return }
        let audioEngine = AVAudioEngine()
        let outputFormat = audioEngine.outputNode.inputFormat(forBus: 0)
        guard outputFormat.sampleRate > 0 && outputFormat.channelCount > 0 else { return }

        let node = AVAudioSourceNode(format: outputFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in ablPointer {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            return noErr
        }

        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: outputFormat)
        audioEngine.mainMixerNode.outputVolume = 0.0

        do {
            try audioEngine.start()
            self.engine = audioEngine
            self.sourceNode = node
            self.isRunning = true
        } catch {
            self.isRunning = false
        }
    }

    public func stop() {
        guard isRunning else { return }
        engine?.stop()
        engine = nil
        sourceNode = nil
        isRunning = false
    }
}

