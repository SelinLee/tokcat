import XCTest
@testable import TokcatKit

final class AppSettingsTests: XCTestCase {
    func testDefaultRoundTripThroughStore() {
        let suiteName = "tokcat.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), .default)

        var settings = AppSettings.default
        settings.showCPU = false
        settings.showNetwork = false
        settings.menuBarShowCPU = true
        settings.menuBarShowMemory = true
        settings.menuBarShowCatIcon = false
        settings.menuBarCatIconScale = 0.75
        settings.menuBarIconStyle = .lineCPU
        settings.showDesktopPet = false
        settings.desktopPetSkin = .procedural
        settings.customPetModelFileName = "demo.usdz"
        settings.pollIntervalSeconds = 7
        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded.clampedPollIntervalSeconds, 7)
        XCTAssertTrue(loaded.showsAnyMenuBarMetric)
        XCTAssertFalse(loaded.menuBarShowCatIcon)
        XCTAssertEqual(loaded.menuBarIconStyle, .lineCPU)
        XCTAssertFalse(loaded.showDesktopPet)
        XCTAssertEqual(loaded.desktopPetSkin, .procedural)
        XCTAssertEqual(loaded.customPetModelFileName, "demo.usdz")
        XCTAssertEqual(loaded.menuBarCatIconPointSize, AppSettings.catIconBasePointSize * (0.5 + 0.75), accuracy: 0.001)
    }

    func testPollIntervalClamping() {
        var settings = AppSettings.default
        settings.pollIntervalSeconds = 0.2
        XCTAssertEqual(settings.clampedPollIntervalSeconds, 1)

        settings.pollIntervalSeconds = 99
        XCTAssertEqual(settings.clampedPollIntervalSeconds, 30)
    }

    func testCatIconScaleClamping() {
        var settings = AppSettings.default
        settings.menuBarCatIconScale = -1
        XCTAssertEqual(settings.clampedCatIconScale, AppSettings.catIconScaleRange.lowerBound)

        settings.menuBarCatIconScale = 3
        XCTAssertEqual(settings.clampedCatIconScale, AppSettings.catIconScaleRange.upperBound)
    }

    func testDefaultScaleIsHalfAndMapsToJustRightSize() {
        let settings = AppSettings.default
        XCTAssertEqual(settings.menuBarCatIconScale, 0.5, accuracy: 0.0001)
        XCTAssertEqual(settings.menuBarCatIconPointSize, AppSettings.catIconBasePointSize, accuracy: 0.001)
        // ±50% around base
        var small = settings
        small.menuBarCatIconScale = 0
        XCTAssertEqual(small.menuBarCatIconPointSize, AppSettings.catIconBasePointSize * 0.5, accuracy: 0.001)
        var large = settings
        large.menuBarCatIconScale = 1
        XCTAssertEqual(large.menuBarCatIconPointSize, AppSettings.catIconBasePointSize * 1.5, accuracy: 0.001)
    }

    func testLegacyAbsoluteScaleMigratesToUIScale() throws {
        let suiteName = "tokcat.tests.scale-v1.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // v1 payload: absolute 1.5 (old "just right") should become UI 50%.
        let legacyJSON = """
        {
          "showCPU": true,
          "showMemory": true,
          "showNetwork": true,
          "showThermal": true,
          "showGPU": true,
          "showTokenSummary": true,
          "showRecentTokenEvents": true,
          "showPetSummary": true,
          "showDesktopPet": true,
          "pollIntervalSeconds": 2,
          "menuBarShowCPU": true,
          "menuBarShowMemory": false,
          "menuBarShowNetwork": false,
          "menuBarShowThermal": false,
          "menuBarShowGPU": false,
          "menuBarShowCatIcon": true,
          "menuBarCatIconScale": 1.5,
          "menuBarIconStyle": "tokcat"
        }
        """.data(using: .utf8)!
        defaults.set(legacyJSON, forKey: AppSettingsStore.defaultsKey)
        let loaded = AppSettingsStore(defaults: defaults).load()
        XCTAssertEqual(loaded.menuBarCatIconScale, 0.5, accuracy: 0.001)
        XCTAssertEqual(loaded.menuBarCatIconPointSize, AppSettings.catIconBasePointSize, accuracy: 0.001)
    }

    func testLegacyMenuBarAccessoryMigration() throws {
        let suiteName = "tokcat.tests.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyJSON = """
        {
          "showCPU": true,
          "showMemory": true,
          "showNetwork": true,
          "showThermal": true,
          "showTokenSummary": true,
          "showRecentTokenEvents": true,
          "showPetSummary": true,
          "showDesktopPet": true,
          "pollIntervalSeconds": 2,
          "menuBarAccessory": "memory"
        }
        """.data(using: .utf8)!
        defaults.set(legacyJSON, forKey: AppSettingsStore.defaultsKey)

        let loaded = AppSettingsStore(defaults: defaults).load()
        XCTAssertFalse(loaded.menuBarShowCPU)
        XCTAssertTrue(loaded.menuBarShowMemory)
        XCTAssertFalse(loaded.menuBarShowNetwork)
        XCTAssertFalse(loaded.menuBarShowThermal)
        // New fields get defaults when absent.
        XCTAssertTrue(loaded.menuBarShowCatIcon)
        XCTAssertEqual(loaded.menuBarCatIconScale, AppSettings.defaultCatIconScale)
        XCTAssertEqual(loaded.menuBarIconStyle, .tokcat)
    }

    func testVerticalOffsetClamping() {
        var settings = AppSettings.default
        settings.menuBarVerticalOffset = -20
        XCTAssertEqual(settings.clampedVerticalOffset, AppSettings.verticalOffsetRange.lowerBound)
        settings.menuBarVerticalOffset = 20
        XCTAssertEqual(settings.clampedVerticalOffset, AppSettings.verticalOffsetRange.upperBound)
        XCTAssertEqual(AppSettings.default.menuBarVerticalOffset, AppSettings.defaultVerticalOffset, accuracy: 0.0001)
        XCTAssertEqual(AppSettings.defaultVerticalOffset, -2.5, accuracy: 0.0001)
    }

    func testTextScaleClamping() {
        var settings = AppSettings.default
        settings.menuBarTextScale = 0.1
        XCTAssertEqual(settings.clampedTextScale, AppSettings.textScaleRange.lowerBound)
        settings.menuBarTextScale = 3
        XCTAssertEqual(settings.clampedTextScale, AppSettings.textScaleRange.upperBound)
        XCTAssertEqual(AppSettings.default.menuBarTextScale, AppSettings.defaultTextScale)
        XCTAssertEqual(AppSettings.defaultTextScale, 1.4, accuracy: 0.0001)
    }

    func testPreferredLayoutDefaults() {
        XCTAssertEqual(AppSettings.defaultCatIconScale, 0.5, accuracy: 0.0001)
        XCTAssertEqual(AppSettings.defaultTextScale, 1.4, accuracy: 0.0001)
        XCTAssertEqual(AppSettings.defaultVerticalOffset, -2.5, accuracy: 0.0001)
        XCTAssertEqual(AppSettings.default.menuBarCatIconScale, 0.5, accuracy: 0.0001)
        XCTAssertEqual(AppSettings.default.menuBarTextScale, 1.4, accuracy: 0.0001)
        XCTAssertEqual(AppSettings.default.menuBarVerticalOffset, -2.5, accuracy: 0.0001)
    }

    func testDefaultShowsCPUOnMenuBar() {
        XCTAssertTrue(AppSettings.default.menuBarShowCPU)
        XCTAssertFalse(AppSettings.default.menuBarShowMemory)
        XCTAssertTrue(AppSettings.default.menuBarShowTokenRate)
        XCTAssertTrue(AppSettings.default.menuBarShowCatIcon)
        XCTAssertTrue(AppSettings.default.showDesktopPet)
    }

    func testDesktopPetSkinDefaultIsPixelTokcat() {
        XCTAssertEqual(AppSettings.default.desktopPetSkin, .pixelTokcat)
        XCTAssertEqual(DesktopPetSkin.allCases.count, 4)
        XCTAssertEqual(DesktopPetSkin.pixelTokcat.displayName, "像素 Tokcat")
        XCTAssertTrue(DesktopPetSkin.pixelTokcat.isPixel)
        XCTAssertEqual(DesktopPetSkin.procedural.displayName, "方块猫")
        XCTAssertEqual(DesktopPetSkin.pinkCat.displayName, "粉猫")
        XCTAssertEqual(DesktopPetSkin.custom.displayName, "自定义")
    }

    func testDesktopPetSkinPersistsAndLegacyDefaultsToPixelTokcat() throws {
        let suiteName = "tokcat.tests.skin.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings.default
        settings.desktopPetSkin = .procedural
        AppSettingsStore(defaults: defaults).save(settings)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).load().desktopPetSkin, .procedural)

        // Legacy payloads without desktopPetSkin default to pixelTokcat.
        let legacyJSON = """
        {
          "showCPU": true,
          "showMemory": true,
          "showNetwork": true,
          "showThermal": true,
          "showGPU": true,
          "showTokenSummary": true,
          "showRecentTokenEvents": true,
          "showPetSummary": true,
          "showDesktopPet": true,
          "pollIntervalSeconds": 2
        }
        """.data(using: .utf8)!
        defaults.set(legacyJSON, forKey: AppSettingsStore.defaultsKey)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).load().desktopPetSkin, .pixelTokcat)
    }

    func testLegacyCatgirlSkinMigratesToPinkCat() throws {
        let suite = "tokcat.tests.catgirl-migrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let payload: [String: Any] = [
            "showCPU": true,
            "showMemory": true,
            "showNetwork": true,
            "showThermal": true,
            "showGPU": true,
            "menuBarShowCPU": true,
            "menuBarShowMemory": false,
            "menuBarShowNetwork": false,
            "menuBarShowThermal": false,
            "menuBarShowGPU": false,
            "menuBarShowCatIcon": true,
            "menuBarCatIconScale": 0.5,
            "menuBarCatIconScaleVersion": 2,
            "menuBarIconStyle": "tokcat",
            "menuBarTextScale": 1.4,
            "menuBarVerticalOffset": -2.5,
            "showTokenSummary": true,
            "showRecentTokenEvents": true,
            "showPetSummary": true,
            "showDesktopPet": true,
            "desktopPetSkin": "catgirl",
            "pollIntervalSeconds": 2,
            "enabledAgentSources": AgentSource.defaultEnabled.map(\.rawValue).sorted()
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        defaults.set(data, forKey: AppSettingsStore.defaultsKey)
        let loaded = AppSettingsStore(defaults: defaults).load()
        XCTAssertEqual(loaded.desktopPetSkin, .pinkCat)
    }


    func testProviderPricingMigrationImportsBotcf() throws {
        let suiteName = "tokcat.tests.pricing-migrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Simulate older settings without botcf rows.
        var old = AppSettings.default
        old.pricingEntries = old.pricingEntries.filter { $0.providerKey == nil }
        let store = AppSettingsStore(defaults: defaults)
        store.save(old)
        defaults.set(false, forKey: AppSettingsStore.migratedProviderPricingKey)

        let loaded = store.load()
        let botcf = loaded.pricingEntries.filter { $0.providerKey?.lowercased() == "botcf" }
        XCTAssertFalse(botcf.isEmpty)
        let sol = try XCTUnwrap(botcf.first { $0.modelKey == "gpt-5.6-sol" })
        XCTAssertEqual(sol.pricing.inputPerMillion, 0.395, accuracy: 0.0001)
    }
    func testPixelTokcatSkinRoundTrip() {
        let suiteName = "tokcat.tests.pixel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(AppSettings.default.desktopPetSkin, .pixelTokcat)
        XCTAssertTrue(DesktopPetSkin.pixelTokcat.isPixel)

        var settings = AppSettings.default
        settings.desktopPetSkin = .pixelTokcat
        store.save(settings)
        XCTAssertEqual(store.load().desktopPetSkin, .pixelTokcat)

        settings.desktopPetSkin = .pinkCat
        store.save(settings)
        XCTAssertEqual(store.load().desktopPetSkin, .pinkCat)
        XCTAssertFalse(DesktopPetSkin.pinkCat.isPixel)
    }

}

final class SystemMetricsMonitorTests: XCTestCase {
    func testPollReturnsFiniteValues() {
        let monitor = SystemMetricsMonitor()
        let first = monitor.poll()
        let second = monitor.poll()

        XCTAssertGreaterThan(first.memoryTotalBytes, 0)
        XCTAssertLessThanOrEqual(first.memoryUsedBytes, first.memoryTotalBytes)
        XCTAssertTrue(second.cpuPercent.isFinite)
        XCTAssertGreaterThanOrEqual(second.cpuPercent, 0)
        XCTAssertLessThanOrEqual(second.cpuPercent, 100)
        XCTAssertTrue(second.networkInBytesPerSecond.isFinite)
        XCTAssertTrue(second.networkOutBytesPerSecond.isFinite)
        XCTAssertTrue(second.gpuPercent.isFinite)
        XCTAssertGreaterThanOrEqual(second.gpuPercent, 0)
        XCTAssertLessThanOrEqual(second.gpuPercent, 100)
    }



    func testEnablePetSoundEffectsDefaultAndPersistence() throws {
        let suiteName = "tokcat.tests.petsfx.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(store.load().enablePetSoundEffects)

        var settings = AppSettings.default
        settings.enablePetSoundEffects = true
        store.save(settings)
        XCTAssertTrue(store.load().enablePetSoundEffects)
    }

}
