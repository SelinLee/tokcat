import XCTest
import Darwin
@testable import TokcatKit

final class NetworkRateSamplerTests: XCTestCase {
    private let wifi = NetworkInterfaceID(index: 4)
    private let tunnel = NetworkInterfaceID(index: 20)

    private func bytes(_ inbound: UInt64, _ outbound: UInt64) -> NetworkByteCounters {
        NetworkByteCounters(inbound: inbound, outbound: outbound)
    }

    func testClosingProxyDropsTunnelWithoutUnderflowOrSmoothingTail() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample(counters: [wifi: bytes(1_000, 500), tunnel: bytes(8_000_000, 4_000_000)], at: 0)
        _ = sampler.sample(counters: [wifi: bytes(2_000, 1_000), tunnel: bytes(9_000_000, 5_000_000)], at: 1)
        let closed = sampler.sample(counters: [wifi: bytes(3_000, 1_500)], at: 2)
        XCTAssertEqual(closed.inbound, 1_000)
        XCTAssertEqual(closed.outbound, 500)
        let next = sampler.sample(counters: [wifi: bytes(4_000, 2_000)], at: 3)
        XCTAssertEqual(next.inbound, 1_000)
        XCTAssertEqual(next.outbound, 500)
    }

    func testNewAndReappearingInterfacesDoNotCountTheirLifetimeTraffic() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample(counters: [wifi: bytes(1_000, 500)], at: 0)
        let opened = sampler.sample(counters: [wifi: bytes(2_000, 1_000), tunnel: bytes(90_000_000, 80_000_000)], at: 1)
        XCTAssertEqual(opened.inbound, 1_000)
        XCTAssertEqual(opened.outbound, 500)
        _ = sampler.sample(counters: [wifi: bytes(3_000, 1_500)], at: 2)
        let reopened = sampler.sample(counters: [wifi: bytes(4_000, 2_000), tunnel: bytes(99_000_000, 89_000_000)], at: 3)
        XCTAssertEqual(reopened.inbound, 1_000)
        XCTAssertEqual(reopened.outbound, 500)
    }

    func testCounterResetIsRebasedAndUnaffectedTrafficIsKept() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample(counters: [wifi: bytes(10_000, 5_000), tunnel: bytes(1_000, 500)], at: 0)
        let reset = sampler.sample(counters: [wifi: bytes(12_000, 6_000), tunnel: bytes(10, 900)], at: 1)
        // Aggregate counts still increase here; an aggregate rollback guard
        // alone would miss the reset and incorrectly subtract the lost bytes.
        XCTAssertEqual(reset.inbound, 2_000)
        XCTAssertEqual(reset.outbound, 1_000)
        let recovered = sampler.sample(counters: [wifi: bytes(13_000, 6_500), tunnel: bytes(1_010, 1_400)], at: 2)
        XCTAssertEqual(recovered.inbound, 2_000)
        XCTAssertEqual(recovered.outbound, 1_000)
    }

    func testOutboundOnlyResetAlsoRebasesInterface() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample(counters: [wifi: bytes(100, 100)], at: 0)
        let reset = sampler.sample(counters: [wifi: bytes(200, 0)], at: 1)
        XCTAssertEqual(reset.inbound, 0)
        XCTAssertEqual(reset.outbound, 0)
    }

    func testAdministrativeChangeWithSameIndexStartsNewBaseline() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample(counters: [wifi: bytes(1_000, 500)], at: 0)
        var replacement = wifi
        replacement.changedAtSeconds = 10
        let changed = sampler.sample(counters: [replacement: bytes(900_000, 800_000)], at: 1)
        XCTAssertEqual(changed.inbound, 0)
        let next = sampler.sample(counters: [replacement: bytes(901_000, 800_500)], at: 2)
        XCTAssertGreaterThan(next.inbound, 0)
        XCTAssertLessThanOrEqual(next.inbound, 1_000)
    }

    func testFailedReadAndAllInterfacesRemovedClearBaselines() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample(counters: [wifi: bytes(1_000, 500)], at: 0)
        _ = sampler.sample(counters: [wifi: bytes(2_000, 1_000)], at: 1)
        XCTAssertEqual(sampler.sample(counters: nil, at: 2).inbound, 0)
        XCTAssertEqual(sampler.sample(counters: [wifi: bytes(900_000, 800_000)], at: 3).inbound, 0)
        XCTAssertEqual(sampler.sample(counters: [:], at: 4).inbound, 0)
        XCTAssertEqual(sampler.sample(counters: [wifi: bytes(999_000, 899_000)], at: 5).inbound, 0)
    }

    func testDuplicateAndOutOfOrderSamplesDoNotMoveBaseline() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample(counters: [wifi: bytes(1_000, 500)], at: 10)
        _ = sampler.sample(counters: [wifi: bytes(1_500, 750)], at: 10)
        _ = sampler.sample(counters: [wifi: bytes(1_800, 900)], at: 9)
        let next = sampler.sample(counters: [wifi: bytes(3_000, 1_500)], at: 12)
        XCTAssertEqual(next.inbound, 1_000)
        XCTAssertEqual(next.outbound, 500)
    }

    func testCrossingFourGiBDoesNotWrap() {
        var sampler = NetworkRateSampler()
        let limit = UInt64(UInt32.max)
        _ = sampler.sample(counters: [wifi: bytes(limit - 100, limit - 50)], at: 0)
        let next = sampler.sample(counters: [wifi: bytes(limit + 100, limit + 50)], at: 1)
        XCTAssertEqual(next.inbound, 200)
        XCTAssertEqual(next.outbound, 100)
    }

    func testNormalRatesUseElapsedTimeAndExponentialSmoothing() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample(counters: [wifi: bytes(0, 0)], at: 0)
        let steady = sampler.sample(counters: [wifi: bytes(2_000, 1_000)], at: 2)
        XCTAssertEqual(steady.inbound, 1_000)
        XCTAssertEqual(steady.outbound, 500)
        let idle = sampler.sample(counters: [wifi: bytes(2_000, 1_000)], at: 3.5)
        XCTAssertEqual(idle.inbound, 1_000 * exp(-1), accuracy: 0.0001)
        XCTAssertEqual(idle.outbound, 500 * exp(-1), accuracy: 0.0001)
    }

    private func message(index: UInt16, flags: Int32 = 0, inbound: UInt64, outbound: UInt64) -> Data {
        var header = if_msghdr2()
        header.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
        header.ifm_version = UInt8(RTM_VERSION)
        header.ifm_type = UInt8(RTM_IFINFO2)
        header.ifm_index = index
        header.ifm_flags = flags
        header.ifm_data.ifi_ibytes = inbound
        header.ifm_data.ifi_obytes = outbound
        return withUnsafeBytes(of: &header) { Data($0) }
    }

    func testReaderPreserves64BitCountsAndSkipsLoopback() throws {
        var data = message(index: 1, flags: IFF_LOOPBACK, inbound: 100, outbound: 100)
        data.append(message(index: 4, inbound: 9_000_000_000, outbound: 8_000_000_000))
        let counters = try XCTUnwrap(NetworkInterfaceReader.parse(data))
        XCTAssertEqual(counters.count, 1)
        XCTAssertEqual(counters[wifi]?.inbound, 9_000_000_000)
        XCTAssertEqual(counters[wifi]?.outbound, 8_000_000_000)
    }

    func testReaderRejectsTruncatedOrInvalidMessagesInsteadOfPartialSnapshot() {
        let valid = message(index: 4, inbound: 10, outbound: 20)
        var truncated = valid
        truncated.append(valid.prefix(8))
        XCTAssertNil(NetworkInterfaceReader.parse(truncated))
        XCTAssertNil(NetworkInterfaceReader.parse(Data([0, 0, UInt8(RTM_VERSION), UInt8(RTM_IFINFO2)])))
        XCTAssertNil(NetworkInterfaceReader.parse(Data([1, 2, 3])))
        XCTAssertEqual(NetworkInterfaceReader.parse(Data())?.count, 0)
    }

    func testLiveReaderReturnsInterfaces() throws {
        let counters = try XCTUnwrap(NetworkInterfaceReader.read())
        XCTAssertFalse(counters.isEmpty)
    }
}
