import Foundation
import Testing
@testable import Notch

@MainActor
struct NotchSettingsTests {
    let suite = "NotchSettingsTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    private func settings() -> NotchSettings {
        NotchSettings(defaults: defaults)
    }

    @Test func everythingIsShownInTheDefaultOrderAtFirst() {
        let settings = settings()
        #expect(settings.featureOrder == NotchFeature.allCases)
        #expect(settings.visibleFeatures == NotchFeature.allCases)
        #expect(settings.hiddenFeatures.isEmpty)
    }

    @Test func hapticsAreOffByDefault() {
        #expect(settings().hapticFeedbackEnabled == false)
    }

    @Test func hidingAndShowingAFeature() {
        let settings = settings()
        settings.setVisible(.calendar, false)
        #expect(!settings.isVisible(.calendar))
        #expect(!settings.visibleFeatures.contains(.calendar))
        #expect(settings.featureOrder.contains(.calendar), "hidden features keep their place in the order")

        settings.setVisible(.calendar, true)
        #expect(settings.isVisible(.calendar))
    }

    @Test func movingAFeatureWorksLikeAListMove() {
        let settings = settings()
        // Drag Now Playing (index 4) to the top.
        settings.moveFeatures(fromOffsets: [4], toOffset: 0)
        #expect(settings.featureOrder == [.nowPlaying, .battery, .timer, .calendar, .files, .systemStats, .levels, .devices, .notes, .calculator, .mirror])
    }

    @Test func choicesSurviveARelaunch() {
        let first = settings()
        first.setVisible(.mirror, false)
        first.moveFeatures(fromOffsets: [2], toOffset: 0)

        let relaunched = settings()
        #expect(relaunched.featureOrder == first.featureOrder)
        #expect(relaunched.hiddenFeatures == [.mirror])
    }

    @Test func resetShowsEverythingInTheDefaultOrder() {
        let settings = settings()
        settings.setVisible(.battery, false)
        settings.moveFeatures(fromOffsets: [0], toOffset: 3)
        settings.resetFeatures()
        #expect(settings.featureOrder == NotchFeature.allCases)
        #expect(settings.hiddenFeatures.isEmpty)
        #expect(self.settings().featureOrder == NotchFeature.allCases, "the reset is saved too")
    }

    @Test func aSavedOrderIsRepaired() {
        // From an older version (no Mirror yet), with a duplicate and a name this version doesn't know.
        defaults.set(["timer", "battery", "timer", "weather"], forKey: "settings.featureOrder")
        #expect(settings().featureOrder == [.timer, .battery, .calendar, .files, .nowPlaying, .systemStats, .levels, .devices, .notes, .calculator, .mirror])
    }

    @Test func changesAreReported() {
        let settings = settings()
        var changes = 0
        settings.onFeaturesChanged = { changes += 1 }
        settings.setVisible(.timer, false)
        settings.moveFeatures(fromOffsets: [0], toOffset: 2)
        settings.resetFeatures()
        #expect(changes == 3)
    }

    @Test func ephemeralSettingsStartFresh() {
        let one = NotchSettings.ephemeral()
        one.setVisible(.battery, false)
        #expect(NotchSettings.ephemeral().hiddenFeatures.isEmpty)
    }
}

@MainActor
struct LookSettingsTests {
    let suite = "LookSettingsTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    @Test func startsWithTodaysLook() {
        let settings = NotchSettings(defaults: defaults)
        #expect(settings.width == .standard)
        #expect(settings.width.points == NotchGeometry.defaultExpandedWidth)
        #expect(settings.cornerRadius == 24)
        #expect(settings.accent == .orange)
        #expect(settings.showsEars)
    }

    @Test func theLookSurvivesARelaunch() {
        let settings = NotchSettings(defaults: defaults)
        settings.width = .wide
        settings.cornerRadius = 30
        settings.accent = .mint
        settings.showsEars = false

        let relaunched = NotchSettings(defaults: defaults)
        #expect(relaunched.width == .wide)
        #expect(relaunched.cornerRadius == 30)
        #expect(relaunched.accent == .mint)
        #expect(!relaunched.showsEars)
    }

    @Test(arguments: [(0.0, 12.0), (50.0, 32.0), (20.0, 20.0)])
    func cornersStayInRange(requested: Double, expected: Double) {
        let settings = NotchSettings(defaults: defaults)
        settings.cornerRadius = requested
        #expect(settings.cornerRadius == expected)
        #expect(NotchSettings(defaults: defaults).cornerRadius == expected)
    }

    @Test func onlyWidthAndEarsChangeTheGeometry() {
        let settings = NotchSettings(defaults: defaults)
        var changes = 0
        settings.onGeometryChanged = { changes += 1 }
        settings.accent = .blue
        settings.cornerRadius = 16
        #expect(changes == 0)
        settings.width = .compact
        settings.showsEars = false
        #expect(changes == 2)
    }

    @Test func resetRestoresTodaysLook() {
        let settings = NotchSettings(defaults: defaults)
        settings.width = .compact
        settings.cornerRadius = 12
        settings.accent = .pink
        settings.showsEars = false
        settings.resetLook()
        #expect(settings.width == .standard && settings.cornerRadius == 24 && settings.accent == .orange && settings.showsEars)
    }

    @Test func unknownSavedValuesFallBackToDefaults() {
        defaults.set("gigantic", forKey: "settings.width")
        defaults.set("chartreuse", forKey: "settings.accent")
        let settings = NotchSettings(defaults: defaults)
        #expect(settings.width == .standard)
        #expect(settings.accent == .orange)
    }

    @Test func widthsGrowInOrder() {
        let points = NotchWidth.allCases.map(\.points)
        #expect(points == points.sorted())
        #expect(Set(points).count == points.count)
    }
}

@MainActor
struct FeatureVisibilityTests {
    private func model() -> (NotchViewModel, NotchSettings) {
        let settings = NotchSettings.ephemeral()
        return (NotchViewModel(geometry: .previewHardware, settings: settings), settings)
    }

    @Test func everyModuleHasItsOwnFeature() {
        let (model, _) = model()
        #expect(Set(model.allModules.map(\.feature)) == Set(NotchFeature.allCases))
        #expect(model.allModules.count == NotchFeature.allCases.count)
    }

    @Test func modulesFollowTheUsersOrder() {
        let (model, settings) = model()
        settings.moveFeatures(fromOffsets: [2], toOffset: 0)   // Calendar first
        #expect(model.modules.map(\.feature).first == .calendar)
        #expect(model.modules.map(\.feature).prefix(3) == [.calendar, .battery, .timer])
    }

    @Test func aHiddenFeatureLeavesTheNotch() {
        let (model, settings) = model()
        settings.setVisible(.mirror, false)
        #expect(!model.modules.contains { $0.feature == .mirror })
        #expect(!model.tabModules.contains { $0.feature == .mirror })
    }

    @Test func aHiddenFeatureGetsNoActivity() {
        let (model, settings) = model()
        settings.setVisible(.battery, false)
        model.showActivity(from: model.battery)
        #expect(model.presentation == .collapsed)

        settings.setVisible(.battery, true)
        model.showActivity(from: model.battery)
        #expect(model.presentation == .activity(model.battery))
    }

    @Test func hidingFilesMeansNoDropTarget() {
        let (model, settings) = model()
        settings.setVisible(.files, false)
        model.expand()
        model.showDropTarget()
        #expect(model.selectedTab == nil)
    }

    @Test func hidingTheOpenTabFallsBackToHome() {
        let (model, settings) = model()
        model.expand()
        model.select(tab: model.shelf)
        settings.setVisible(.files, false)
        #expect(model.selectedTabModule == nil)
    }
}
