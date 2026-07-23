import Foundation

#if os(macOS)
import Darwin
#endif

public struct AgentRuntimeEnvironmentDescription: Sendable, Equatable {
    public var deviceType: String
    public var hardwareModel: String?
    public var architecture: String
    public var operatingSystemName: String
    public var operatingSystemVersion: String
    public var operatingSystemDescription: String

    public init(
        deviceType: String,
        hardwareModel: String? = nil,
        architecture: String,
        operatingSystemName: String,
        operatingSystemVersion: String,
        operatingSystemDescription: String
    ) {
        self.deviceType = deviceType
        self.hardwareModel = hardwareModel
        self.architecture = architecture
        self.operatingSystemName = operatingSystemName
        self.operatingSystemVersion = operatingSystemVersion
        self.operatingSystemDescription = operatingSystemDescription
    }

    public static func current(processInfo: ProcessInfo = .processInfo) -> Self {
        let version = processInfo.operatingSystemVersion
        return Self(
            deviceType: platformDeviceType,
            hardwareModel: hardwareModelIdentifier(),
            architecture: processArchitecture,
            operatingSystemName: operatingSystemName,
            operatingSystemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            operatingSystemDescription: processInfo.operatingSystemVersionString
        )
    }

    public var promptSection: String {
        let model = hardwareModel.map { "; hardware model: \($0)" } ?? ""
        return """
        ## Runtime Environment
        - Connor is running on the user's current \(deviceType)\(model); processor architecture: \(architecture).
        - Operating system: \(operatingSystemName) \(operatingSystemVersion); system version description: \(operatingSystemDescription).
        - Use this as authoritative runtime context when system compatibility, paths, commands, applications, permissions, or device capabilities matter. Do not infer that a tool, permission, application, or hardware capability is available merely because the operating system normally supports it.
        """
    }

    private static var platformDeviceType: String {
        #if os(macOS)
        "Mac"
        #elseif os(iOS)
        "iPhone or iPad"
        #elseif os(tvOS)
        "Apple TV"
        #elseif os(watchOS)
        "Apple Watch"
        #elseif os(Linux)
        "Linux device"
        #elseif os(Windows)
        "Windows device"
        #else
        "device"
        #endif
    }

    private static var operatingSystemName: String {
        #if os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #elseif os(tvOS)
        "tvOS"
        #elseif os(watchOS)
        "watchOS"
        #elseif os(Linux)
        "Linux"
        #elseif os(Windows)
        "Windows"
        #else
        "Unknown OS"
        #endif
    }

    private static var processArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #elseif arch(arm)
        "arm"
        #elseif arch(i386)
        "i386"
        #else
        "unknown"
        #endif
    }

    private static func hardwareModelIdentifier() -> String? {
        #if os(macOS)
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &value, &size, nil, 0) == 0 else { return nil }
        let bytes = value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let model = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? nil : model
        #else
        return nil
        #endif
    }
}
