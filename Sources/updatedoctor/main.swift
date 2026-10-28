import Foundation
import UpdateDoctorKit

let usage = """
updatedoctor \(UpdateDoctorVersion.current)
Explains why a Mac did not install a macOS update. Read only, changes nothing.

Usage:
  updatedoctor doctor [--json | --ea] [--quick] [--offline] [--logs]
  updatedoctor version
  updatedoctor help

Options:
  --json     Print the full report as JSON.
  --ea       Print one line for a Jamf Pro Extension Attribute.
  --quick    Skip `softwareupdate -l` (it can take a minute).
  --offline  Skip the Apple GDMF feed and host reachability checks.
  --logs     Also count recent softwareupdated and mobileassetd errors in the unified log.

Run with sudo for the Bootstrap Token check. Without root it is skipped and reported as skipped.
Exit codes: 0 healthy or at risk, 2 blocked, 64 usage error.
\(UpdateDoctorVersion.repositoryURL)
"""

var args = Array(CommandLine.arguments.dropFirst())
let command = args.first.flatMap { $0.hasPrefix("-") ? nil : $0 } ?? "doctor"
if !args.isEmpty && !args[0].hasPrefix("-") { args.removeFirst() }

switch command {
case "version", "--version":
    print("updatedoctor \(UpdateDoctorVersion.current)")
    exit(0)
case "help", "--help", "-h":
    print(usage)
    exit(0)
case "doctor":
    break
default:
    FileHandle.standardError.write(Data("Unknown command: \(command)\n\n\(usage)\n".utf8))
    exit(64)
}

var options = DoctorOptions()
var format = "text"
for arg in args {
    switch arg {
    case "--json": format = "json"
    case "--ea": format = "ea"
    case "--quick": options.quick = true
    case "--offline": options.offline = true
    case "--logs": options.includeLogs = true
    case "--version": print("updatedoctor \(UpdateDoctorVersion.current)"); exit(0)
    case "--help", "-h": print(usage); exit(0)
    default:
        FileHandle.standardError.write(Data("Unknown option: \(arg)\n\n\(usage)\n".utf8))
        exit(64)
    }
}

let report = Doctor(probe: LiveProbe(), options: options).run()
switch format {
case "json": print(Output.json(report))
case "ea": print(Output.jamfEA(report))
default: print(Output.text(report))
}
exit(report.verdict == "BLOCKED" ? 2 : 0)
