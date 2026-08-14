import Foundation

/// 16-bit mono PCM WAVE. Used by tests and the recorder’s transcribe payload.
public enum AudioWAV {
    public static func pcm16Mono(sampleRate: Int = 16_000, samples: [Int16]) -> Data {
        let dataSize = samples.count * 2
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(littleEndianUInt32(UInt32(36 + dataSize)))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(littleEndianUInt32(16))
        data.append(littleEndianUInt16(1))
        data.append(littleEndianUInt16(1))
        data.append(littleEndianUInt32(UInt32(sampleRate)))
        data.append(littleEndianUInt32(UInt32(sampleRate * 2)))
        data.append(littleEndianUInt16(2))
        data.append(littleEndianUInt16(16))
        data.append(contentsOf: Array("data".utf8))
        data.append(littleEndianUInt32(UInt32(dataSize)))
        for sample in samples {
            var value = sample.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }

    public static func silent(sampleRate: Int = 16_000, milliseconds: Int = 40) -> Data {
        let count = max(1, sampleRate * milliseconds / 1000)
        return pcm16Mono(sampleRate: sampleRate, samples: Array(repeating: 0, count: count))
    }

    private static func littleEndianUInt16(_ value: UInt16) -> Data {
        var next = value.littleEndian
        return withUnsafeBytes(of: &next) { Data($0) }
    }

    private static func littleEndianUInt32(_ value: UInt32) -> Data {
        var next = value.littleEndian
        return withUnsafeBytes(of: &next) { Data($0) }
    }
}
