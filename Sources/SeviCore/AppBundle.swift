import Foundation

/// Finds the app bundle an executable belongs to.
public enum AppBundle {
    /// The `.app` folder containing the executable at `path`, following links
    /// first, or nil when the real file is not at `<name>.app/Contents/MacOS/`.
    ///
    /// Links matter because a package manager puts a link to the command in a
    /// folder on the PATH. Started through that link, the command would
    /// otherwise look for its bundle next to the link and find nothing.
    public static func containing(executable path: String) -> String? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let macOS = resolved.deletingLastPathComponent()
        let contents = macOS.deletingLastPathComponent()
        let bundle = contents.deletingLastPathComponent()
        guard macOS.lastPathComponent == "MacOS",
              contents.lastPathComponent == "Contents",
              bundle.pathExtension == "app"
        else {
            return nil
        }
        return bundle.path
    }
}
