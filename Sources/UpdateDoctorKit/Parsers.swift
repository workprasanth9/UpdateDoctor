import Foundation

/// Pure parsing helpers. Each one takes raw text or data captured from a macOS
/// command or file and returns structured values. Tests feed them fixtures.
public enum Parsers {

    // MARK: Versions

    /// Compares dotted versions such as "26.7" and "26.7.2". Missing parts count as 0.
    public static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    public static func majorVersion(_ v: String) -> Int {
        Int(v.split(separator: ".").first ?? "") ?? 0
    }

    // MARK: sw_vers

    public struct OSInfo: Equatable {
        public let productVersion: String
        public let buildVersion: String
    }

    public static func swVers(_ text: String) -> OSInfo? {
        var version: String?
        var build: String?
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "ProductVersion" { version = parts[1] }
            if parts[0] == "BuildVersion" { build = parts[1] }
        }
        guard let v = version else { return nil }
        return OSInfo(productVersion: v, buildVersion: build ?? "")
    }

    // MARK: ioreg device identifiers

    /// Extracts identifiers Apple uses in the GDMF SupportedDevices list.
    /// Apple silicon Macs report a target-type such as J713, listed in GDMF as J713AP.
    /// Intel Macs report a board-id such as Mac-1E7E29AD0135F9BC.
    public static func deviceIdentifiers(ioreg text: String) -> [String] {
        var ids: [String] = []
        if let target = quotedValue(for: "target-type", in: text) { ids.append(target + "AP") }
        if let board = quotedValue(for: "board-id", in: text) { ids.append(board) }
        return ids
    }

    private static func quotedValue(for key: String, in text: String) -> String? {
        for line in text.split(separator: "\n") where line.contains("\"\(key)\"") {
            // Format: "target-type" = <"J713">
            guard let open = line.range(of: "<\""), let close = line.range(of: "\">", range: open.upperBound..<line.endIndex) else { continue }
            let value = line[open.upperBound..<close.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            if !value.isEmpty { return value }
        }
        return nil
    }

    // MARK: GDMF

    public struct GDMFRelease: Equatable {
        public let version: String
        public let build: String
        public let postingDate: String
        public let supportedDevices: [String]
    }

    /// Parses Apple's public GDMF feed (https://gdmf.apple.com/v2/pmv), macOS public asset sets.
    public static func gdmfReleases(_ data: Data) -> [GDMFRelease]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sets = json["PublicAssetSets"] as? [String: Any],
              let mac = sets["macOS"] as? [[String: Any]] else { return nil }
        return mac.compactMap { entry in
            guard let v = entry["ProductVersion"] as? String else { return nil }
            return GDMFRelease(version: v,
                               build: entry["Build"] as? String ?? "",
                               postingDate: entry["PostingDate"] as? String ?? "",
                               supportedDevices: entry["SupportedDevices"] as? [String] ?? [])
        }
    }

    /// Newest release in the same major version that lists one of the device identifiers.
    public static func latestRelease(_ releases: [GDMFRelease], major: Int, devices: [String]) -> GDMFRelease? {
        let lowered = Set(devices.map { $0.lowercased() })
        return releases
            .filter { majorVersion($0.version) == major }
            .filter { r in lowered.isEmpty || r.supportedDevices.contains { lowered.contains($0.lowercased()) } }
            .max { compareVersions($0.version, $1.version) == .orderedAscending }
    }

    // MARK: softwareupdate -l

    public struct PendingUpdate: Equatable {
        public let label: String
        public let title: String
        public let version: String
        public let requiresRestart: Bool
    }

    public static func softwareUpdateList(_ text: String) -> [PendingUpdate] {
        var result: [PendingUpdate] = []
        var label: String?
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("* Label:") {
                label = line.dropFirst("* Label:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Title:"), let l = label {
                var fields: [String: String] = [:]
                for part in line.split(separator: ",") {
                    let kv = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if kv.count == 2 { fields[kv[0]] = kv[1] }
                }
                result.append(PendingUpdate(label: l, title: fields["Title"] ?? l,
                                            version: fields["Version"] ?? "",
                                            requiresRestart: fields["Action"] == "restart"))
                label = nil
            }
        }
        return result
    }

    // MARK: pmset -g batt

    public struct PowerInfo: Equatable {
        public let onACPower: Bool
        public let batteryPercent: Int?
    }

    public static func pmsetBattery(_ text: String) -> PowerInfo {
        let onAC = text.contains("'AC Power'")
        var percent: Int?
        if let range = text.range(of: #"(\d{1,3})%"#, options: .regularExpression) {
            percent = Int(text[range].dropLast())
        }
        return PowerInfo(onACPower: onAC, batteryPercent: percent)
    }

    // MARK: diskutil info -plist /

    public static func containerFreeBytes(diskutilPlist data: Data) -> Int64? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        if let n = plist["APFSContainerFree"] as? NSNumber { return n.int64Value }
        if let n = plist["FreeSpace"] as? NSNumber { return n.int64Value }
        return nil
    }

    // MARK: profiles

    public struct Enrollment: Equatable {
        public let enrolledViaDEP: Bool
        public let mdmEnrolled: Bool
        public let userApproved: Bool
    }

    public static func enrollment(_ text: String) -> Enrollment {
        var dep = false, mdm = false, approved = false
        for line in text.split(separator: "\n") {
            let l = line.lowercased()
            if l.hasPrefix("enrolled via dep:") { dep = l.contains("yes") }
            if l.hasPrefix("mdm enrollment:") {
                mdm = l.contains("yes")
                approved = l.contains("user approved")
            }
        }
        return Enrollment(enrolledViaDEP: dep, mdmEnrolled: mdm, userApproved: approved)
    }

    public struct BootstrapToken: Equatable {
        public let supportedOnServer: Bool?
        public let escrowed: Bool?
    }

    public static func bootstrapToken(_ text: String) -> BootstrapToken {
        var supported: Bool?, escrowed: Bool?
        for line in text.split(separator: "\n") {
            let l = line.lowercased()
            if l.contains("supported on server:") { supported = l.contains("yes") }
            if l.contains("escrowed to server:") { escrowed = l.contains("yes") }
        }
        return BootstrapToken(supportedOnServer: supported, escrowed: escrowed)
    }

    public static func fileVaultOn(_ text: String) -> Bool? {
        if text.contains("FileVault is On") { return true }
        if text.contains("FileVault is Off") { return false }
        return nil
    }

    // MARK: plists

    public static func plist(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }
}
