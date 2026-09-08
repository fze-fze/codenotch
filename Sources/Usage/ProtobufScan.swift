import Foundation

/// A deliberately small, defensive reader for the protobuf wire format.
///
/// Antigravity stores its generation records as serialized protobuf and ships
/// no descriptors, so fields can only be addressed by number. Nothing here
/// trusts the input: a truncated length, an unknown wire type, or a zero field
/// number ends the scan and keeps whatever was already read, because a record
/// that is only partly readable still carries real tokens. Reading never throws
/// and never reaches outside the buffer.
struct ProtobufMessage {
    enum Value: Equatable {
        case varint(UInt64)
        case bytes([UInt8])
        case fixed32(UInt32)
        case fixed64(UInt64)
    }

    private let bytes: [UInt8]

    init(_ data: Data) { self.bytes = [UInt8](data) }
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    /// Every top-level field, in encounter order. Repeated fields appear once
    /// per occurrence rather than being collapsed.
    var fields: [(number: Int, value: Value)] {
        var out: [(number: Int, value: Value)] = []
        var index = 0
        while index < bytes.count {
            guard let (tag, afterTag) = varint(from: index) else { return out }
            let number = Int(truncatingIfNeeded: tag >> 3)
            guard number > 0 else { return out }
            index = afterTag
            switch tag & 7 {
            case 0:
                guard let (value, next) = varint(from: index) else { return out }
                out.append((number, .varint(value)))
                index = next
            case 1:
                guard bytes.count - index >= 8 else { return out }
                out.append((number, .fixed64(fixedWidth(at: index, count: 8))))
                index += 8
            case 2:
                guard let (length, start) = varint(from: index),
                      length <= UInt64(bytes.count - start) else { return out }
                let end = start + Int(length)
                out.append((number, .bytes(Array(bytes[start..<end]))))
                index = end
            case 5:
                guard bytes.count - index >= 4 else { return out }
                out.append((number, .fixed32(UInt32(truncatingIfNeeded: fixedWidth(at: index, count: 4)))))
                index += 4
            default:
                // Groups (3, 4) were removed from proto3 and nothing here emits them.
                return out
            }
        }
        return out
    }

    /// The first varint carried by `number`, if the field is present and is one.
    func varint(_ number: Int) -> UInt64? {
        for field in fields where field.number == number {
            if case .varint(let value) = field.value { return value }
        }
        return nil
    }

    func bytes(_ number: Int) -> [UInt8]? {
        for field in fields where field.number == number {
            if case .bytes(let value) = field.value { return value }
        }
        return nil
    }

    func message(_ number: Int) -> ProtobufMessage? { bytes(number).map(ProtobufMessage.init) }

    /// Nested lookup, so a field buried three levels down reads as one call.
    func message(path: [Int]) -> ProtobufMessage? {
        path.reduce(self) { $0?.message($1) }
    }

    func string(_ number: Int) -> String? {
        bytes(number).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    /// A packed repeated varint field. Antigravity writes the step indices a
    /// generation covers this way.
    func packedVarints(_ number: Int) -> [UInt64] {
        guard let payload = bytes(number) else { return [] }
        var out: [UInt64] = []
        var index = 0
        while index < payload.count {
            guard let (value, next) = Self.varint(in: payload, from: index) else { return out }
            out.append(value)
            index = next
        }
        return out
    }

    // MARK: - Wire primitives

    private func varint(from index: Int) -> (UInt64, Int)? {
        Self.varint(in: bytes, from: index)
    }

    /// Stops at ten bytes: that is the widest a 64-bit varint can legally be,
    /// and a longer run means the buffer is not what it claims to be.
    static func varint(in bytes: [UInt8], from index: Int) -> (UInt64, Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var cursor = index
        while cursor < bytes.count {
            let byte = bytes[cursor]
            cursor += 1
            result |= UInt64(byte & 0x7F) &<< shift
            if byte & 0x80 == 0 { return (result, cursor) }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    private func fixedWidth(at index: Int, count: Int) -> UInt64 {
        var value: UInt64 = 0
        for offset in (0..<count).reversed() {
            value = value &<< 8 | UInt64(bytes[index + offset])
        }
        return value
    }
}
