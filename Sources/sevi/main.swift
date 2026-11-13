import Foundation

let usage = """
    usage: sevi <command>

      daemon [--for <seconds>]   listen and publish sound levels; started by
                                 opening Sevi.app, not from a shell
      stop                       stop listening now
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
case nil:
    print(usage)
default:
    fail(usage)
}
