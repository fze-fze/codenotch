import Foundation

/// Just enough of the protobuf wire format to read another program's records.
///
/// Antigravity writes its token accounting as serialized protobuf inside
/// SQLite blobs and ships no `.proto` to go with it. It does not need to: the
/// wire format is self-describing enough to walk without a schema. Every field
/// announces its number and how to find its end, so a reader that knows which
/// numbers it wants can step over everything else without understanding any of
/// it. The field *numbers* this file's callers use were read out of the
/// descriptor Antigravity's own language server carries, so they are the
/// program's own definitions rather than a guess.
///
/// Two wire types are decoded, because two are all that carry anything here:
/// varints and length-delimited blobs. The fixed-width types are stepped over
/// by their known size. An unrecognised wire type ends the scan and fails the
/// whole message — the alternative is guessing at a length and resuming in the
/// middle of some other value, which does not produce an error, it produces a
/// plausible wrong number.
struct ProtobufMessage {
    private var varints: [Int: [UInt64]] = [:]
    private var blobs: [Int: [Data]] = [:]

    /// Fails rather than returning a partial message. A blob that stops making
    /// sense half way through is not a record with some fields missing, it is a
    /// record whose remaining fields landed at unknown offsets.
    init?(_ data: Data) {
        var index = data.startIndex
        while index < data.endIndex {
            guard let (key, afterKey) = Self.varint(data, index) else { return nil }
            index = afterKey
            let field = Int(truncatingIfNeeded: key >> 3)
            guard field > 0 else { return nil }
            switch key & 0b111 {
            case 0:
                guard let (value, next) = Self.varint(data, index) else { return nil }
                varints[field, default: []].append(value)
                index = next
            case 2:
                guard let (length, afterLength) = Self.varint(data, index),
                      let count = Int(exactly: length) else { return nil }
                // Reported rather than trapping: the length is a number read
                // out of a file, so a corrupt one is an expected input.
                let (end, overflowed) = afterLength.addingReportingOverflow(count)
                guard !overflowed, end <= data.endIndex else { return nil }
                blobs[field, default: []].append(Data(data[afterLength..<end]))
                index = end
            case 1, 5:
                let width = (key & 0b111) == 1 ? 8 : 4
                let end = index.advanced(by: width)
                guard end <= data.endIndex else { return nil }
                index = end
            default:
                // Groups (3 and 4) were removed from the language decades ago,
                // and 6/7 have never meant anything.
                return nil
            }
        }
    }

    /// Base-128 varint. Refuses anything longer than the ten bytes a 64-bit
    /// value can occupy, so a run of continuation bits cannot spin.
    private static func varint(_ data: Data, _ start: Int) -> (UInt64, Int)? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var index = start
        while index < data.endIndex {
            let byte = data[index]
            index += 1
            if shift < 64 { value |= UInt64(byte & 0x7F) << shift }
            shift += 7
            if byte & 0x80 == 0 { return (value, index) }
            if shift > 63 { return nil }
        }
        return nil
    }

    /// The last value wins, which is what protobuf itself specifies for a
    /// repeated appearance of a non-repeated field.
    func integer(_ field: Int) -> UInt64? { varints[field]?.last }

    /// Clamped into `Int64`, because that is what the token counts are stored
    /// in and a value that does not fit is not a token count.
    func count(_ field: Int) -> Int64 {
        guard let value = integer(field), value <= UInt64(Int64.max) else { return 0 }
        return Int64(value)
    }

    func data(_ field: Int) -> Data? { blobs[field]?.last }

    func string(_ field: Int) -> String? {
        guard let raw = data(field) else { return nil }
        return String(data: raw, encoding: .utf8)
    }

    func message(_ field: Int) -> ProtobufMessage? {
        guard let raw = data(field) else { return nil }
        return ProtobufMessage(raw)
    }

    func messages(_ field: Int) -> [ProtobufMessage] {
        (blobs[field] ?? []).compactMap(ProtobufMessage.init)
    }
}
