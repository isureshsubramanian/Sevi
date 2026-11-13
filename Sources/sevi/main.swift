import Foundation

let usage = """
    usage: sevi <command>

      daemon [--for <seconds>]   listen and publish sound levels; started by
                                 opening Sevi.app, not from a shell
      stop                       stop listening now
      init zsh                   print the line to add to your .zshrc
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(64)
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "daemon":
    var maxSeconds: Double?
    let options = Array(arguments.dropFirst())
    if !options.isEmpty {
        guard options.count == 2, options[0] == "--for",
              let seconds = Double(options[1]), seconds > 0, seconds.isFinite
        else {
            fail(usage)
        }
        maxSeconds = seconds
    }
    runDaemon(maxSeconds: maxSeconds)
case "stop":
    guard arguments.count == 1 else { fail(usage) }
    exit(runStop())
case "init":
    guard arguments.count == 2, arguments[1] == "zsh" else { fail(usage) }
    guard let plugin = Bundle.main.path(forResource: "sevi.plugin", ofType: "zsh") else {
        fail("The prompt plugin is missing from this copy of Sevi.")
    }
    // Sevi never edits .zshrc itself; this only prints the line.
    let quoted = "'" + plugin.replacingOccurrences(of: "'", with: "'\\''") + "'"
    print("# Add this line to ~/.zshrc, after your theme or Oh My Zsh is loaded:")
    print("source \(quoted)")
case nil:
    print(usage)
default:
    fail(usage)
}
