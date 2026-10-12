import AVFoundation
import Foundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var isRunning = false

    var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }

    func start() throws {
        stopEngine()
        lock.lock()
        samples = []
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        else {
            throw VoxError.audioFormat
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer: buffer, targetFormat: targetFormat)
        }
        try engine.start()
        isRunning = true
    }

    func stop() -> [Float] {
        stopEngine()
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    private func stopEngine() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        converter = nil
    }

    private func append(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }
        var error: NSError?
        var consumed = false
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = converted.floatChannelData?[0] else { return }
        let count = Int(converted.frameLength)
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        lock.unlock()
    }
}
