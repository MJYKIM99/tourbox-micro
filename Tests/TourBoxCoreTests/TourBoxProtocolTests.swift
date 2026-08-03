import Foundation
import Testing
@testable import TourBoxCore

@Test func decodesOfficialTourBoxCodes() {
    #expect(TourBoxProtocolDecoder.decode(code: 196) == .init(control: .knob, phase: .step(1)))
    #expect(TourBoxProtocolDecoder.decode(code: 132) == .init(control: .knob, phase: .step(-1)))
    #expect(TourBoxProtocolDecoder.decode(code: 3) == .init(control: .short, phase: .pressed))
    #expect(TourBoxProtocolDecoder.decode(code: 131) == .init(control: .short, phase: .released))
    #expect(TourBoxProtocolDecoder.decode(code: 42) == .init(control: .tour, phase: .pressed))
    #expect(TourBoxProtocolDecoder.decode(code: 255) == nil)
}

@Test func decodesFinalByteLikeOfficialService() {
    let packet = Data([0x7f, 0x00, 0xc4])
    #expect(TourBoxProtocolDecoder.decode(packet) == .init(control: .knob, phase: .step(1)))
}
