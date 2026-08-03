import Foundation

public enum TourBoxControl: String, CaseIterable, Codable, Hashable, Sendable {
    case knob
    case scroll
    case dial
    case tall
    case short
    case top
    case side
    case up
    case down
    case left
    case right
    case tour
    case c1
    case c2
}

public enum TourBoxPhase: Equatable, Sendable {
    case pressed
    case released
    case step(Int)
}

public struct TourBoxEvent: Equatable, Sendable {
    public let control: TourBoxControl
    public let phase: TourBoxPhase

    public init(control: TourBoxControl, phase: TourBoxPhase) {
        self.control = control
        self.phase = phase
    }
}

/// Decodes the final byte of each TourBox Console Max/MSP TCP message.
///
/// TourBox's official sample service listens on TCP 50500 and treats the final
/// byte as the control event. Keeping that behavior here makes the bridge
/// compatible with the vendor's Max/MSP preset without bundling Max itself.
public enum TourBoxProtocolDecoder {
    public static func decode(_ data: Data) -> TourBoxEvent? {
        guard let code = data.last else { return nil }
        return decode(code: code)
    }

    public static func decode(code: UInt8) -> TourBoxEvent? {
        eventMap[code]
    }

    private static let eventMap: [UInt8: TourBoxEvent] = [
        196: .init(control: .knob, phase: .step(1)),
        132: .init(control: .knob, phase: .step(-1)),
        55: .init(control: .knob, phase: .pressed),
        183: .init(control: .knob, phase: .released),

        201: .init(control: .scroll, phase: .step(1)),
        137: .init(control: .scroll, phase: .step(-1)),
        10: .init(control: .scroll, phase: .pressed),
        138: .init(control: .scroll, phase: .released),

        207: .init(control: .dial, phase: .step(1)),
        143: .init(control: .dial, phase: .step(-1)),
        56: .init(control: .dial, phase: .pressed),
        184: .init(control: .dial, phase: .released),

        0: .init(control: .tall, phase: .pressed),
        128: .init(control: .tall, phase: .released),
        3: .init(control: .short, phase: .pressed),
        131: .init(control: .short, phase: .released),
        2: .init(control: .top, phase: .pressed),
        130: .init(control: .top, phase: .released),
        1: .init(control: .side, phase: .pressed),
        129: .init(control: .side, phase: .released),

        16: .init(control: .up, phase: .pressed),
        144: .init(control: .up, phase: .released),
        17: .init(control: .down, phase: .pressed),
        145: .init(control: .down, phase: .released),
        18: .init(control: .left, phase: .pressed),
        146: .init(control: .left, phase: .released),
        19: .init(control: .right, phase: .pressed),
        147: .init(control: .right, phase: .released),

        42: .init(control: .tour, phase: .pressed),
        170: .init(control: .tour, phase: .released),
        34: .init(control: .c1, phase: .pressed),
        162: .init(control: .c1, phase: .released),
        35: .init(control: .c2, phase: .pressed),
        163: .init(control: .c2, phase: .released)
    ]
}
