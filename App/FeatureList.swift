import TrebleCore

#if DEBUG
import SampleModule
#endif

/// Every feature compiled into Treble, in the order they appear in Settings
/// and the panel. Adding a feature = one import + one line here.
/// Removing one = delete its line (and its folder), and everything still builds.
enum FeatureList {
    @MainActor
    static var all: [any TrebleModule.Type] {
        var modules: [any TrebleModule.Type] = []
        #if DEBUG
        modules.append(SampleModule.self)
        #endif
        return modules
    }
}
