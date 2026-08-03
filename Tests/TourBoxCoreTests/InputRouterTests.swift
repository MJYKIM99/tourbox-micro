import Testing
@testable import TourBoxCore

@Test func mapsPrimaryCodexControls() {
    var router = InputRouter()
    #expect(router.route(.init(control: .top, phase: .pressed)) == [.newIndependentChat])
    #expect(router.route(.init(control: .c1, phase: .pressed)) == [.copy])
    #expect(router.route(.init(control: .c2, phase: .pressed)) == [.paste])
    #expect(router.route(.init(control: .up, phase: .pressed)) == [.screenshot])
    #expect(router.route(.init(control: .right, phase: .pressed)) == [.nextRecentChat])
    #expect(router.route(.init(control: .down, phase: .pressed)) == [.openReview])
    #expect(router.route(.init(control: .left, phase: .pressed)) == [.previousRecentChat])
    #expect(router.route(.init(control: .dial, phase: .pressed)) == [.searchChats])
    #expect(router.route(.init(control: .knob, phase: .step(-1))) == [.adjustReasoning(-1)])
    #expect(router.route(.init(control: .dial, phase: .step(1))) == [.nextChat])
}

@Test func preservesPushToTalkPressAndRelease() {
    var router = InputRouter()
    #expect(router.route(.init(control: .short, phase: .pressed)) == [.voice(pressed: true)])
    #expect(router.route(.init(control: .short, phase: .released)) == [.voice(pressed: false)])
}

@Test func tourLayerTriggersSecondaryCodexActionsAndSuppressesBaseAction() {
    let mappings: [(TourBoxControl, MicroAction)] = [
        (.knob, .quickChat),
        (.scroll, .findInChat),
        (.dial, .openCommandMenu),
        (.top, .searchFiles)
    ]

    for (control, expectedAction) in mappings {
        var router = InputRouter()
        #expect(router.route(.init(control: .tour, phase: .pressed)).isEmpty)
        #expect(router.route(.init(control: control, phase: .pressed)) == [expectedAction])
        #expect(router.route(.init(control: control, phase: .released)).isEmpty)
        #expect(router.route(.init(control: .tour, phase: .released)).isEmpty)
    }
}

@Test func tourLayerSelectsSixSlotsAndSuppressesBaseAction() {
    let controls: [TourBoxControl] = [.c1, .c2, .up, .right, .down, .left]
    for (offset, control) in controls.enumerated() {
        var router = InputRouter()
        #expect(router.route(.init(control: .tour, phase: .pressed)).isEmpty)
        #expect(router.route(.init(control: control, phase: .pressed)) == [.openSlot(offset + 1)])
        #expect(router.route(.init(control: control, phase: .released)).isEmpty)
        #expect(router.route(.init(control: .tour, phase: .released)).isEmpty)
    }
}

@Test func tappingTourTogglesHUD() {
    var router = InputRouter()
    #expect(router.route(.init(control: .tour, phase: .pressed)).isEmpty)
    #expect(router.route(.init(control: .tour, phase: .released)) == [.toggleHUD])
}

@Test func supportsPersistedButtonRemappingWithoutChangingHoldControls() {
    var mapping = InputMappingConfiguration.default
    mapping.set(.togglePlan, for: .top)
    mapping.set(.none, for: .c1)
    var router = InputRouter(configuration: mapping)

    #expect(router.route(.init(control: .top, phase: .pressed)) == [.togglePlan])
    #expect(router.route(.init(control: .c1, phase: .pressed)).isEmpty)
    #expect(router.route(.init(control: .short, phase: .pressed)) == [.voice(pressed: true)])
    #expect(router.route(.init(control: .short, phase: .released)) == [.voice(pressed: false)])
}
