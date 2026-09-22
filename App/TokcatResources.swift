import Foundation

/// SwiftPM's generated accessor can point at the build directory. Packaged apps
/// must load their own resources so the status icon and pet also work after moving.
enum TokcatResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Tokcat_TokcatApp.bundle"),
           let packaged = Bundle(url: url) {
            return packaged
        }
        return Bundle.module
    }()
}
