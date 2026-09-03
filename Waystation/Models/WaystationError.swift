import Foundation

/// Unified strongly-typed error enumeration for Waystation.
/// Conforms to `LocalizedError` with `errorDescription`, `failureReason`, and `recoverySuggestion` as required by AD-8.
public enum WaystationError: LocalizedError, Sendable, Equatable {
    case commandLineToolsMissing
    case converterMissing
    case processExecutionFailed(command: String, exitCode: Int32, output: String)
    case conversionFailed(reason: String, exitCode: Int32)
    case invalidManifest(reason: String)
    case incompatibleAPIs(apis: [String])
    case downloadFailed(reason: String)
    case unarchiveFailed(reason: String)
    case projectBuildFailed(reason: String)
    case signingFailed(reason: String)
    case appLaunchFailed(reason: String)
    case registryError(reason: String)

    public var errorDescription: String? {
        switch self {
        case .commandLineToolsMissing:
            return "Xcode Command Line Tools Missing"
        case .converterMissing:
            return "Safari Web Extension Converter Not Found"
        case .processExecutionFailed(let command, let exitCode, _):
            return "Command '\(command)' failed with exit code \(exitCode)"
        case .conversionFailed(let reason, let exitCode):
            return "Safari conversion failed (code \(exitCode)): \(reason)"
        case .invalidManifest(let reason):
            return "Invalid manifest.json: \(reason)"
        case .incompatibleAPIs(let apis):
            return "Incompatible Chrome APIs detected: \(apis.joined(separator: ", "))"
        case .downloadFailed(let reason):
            return "Failed to download extension: \(reason)"
        case .unarchiveFailed(let reason):
            return "Failed to unpack extension: \(reason)"
        case .projectBuildFailed(let reason):
            return "Failed to build container app: \(reason)"
        case .signingFailed(let reason):
            return "Code signing failed: \(reason)"
        case .appLaunchFailed(let reason):
            return "Failed to launch container app: \(reason)"
        case .registryError(let reason):
            return "Registry error: \(reason)"
        }
    }

    public var failureReason: String? {
        switch self {
        case .commandLineToolsMissing:
            return "The required Xcode command-line developer tools are not installed or configured on this Mac."
        case .converterMissing:
            return "'safari-web-extension-converter' could not be located via xcrun."
        case .processExecutionFailed(_, let exitCode, let output):
            return "Process exited with code \(exitCode). Details: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .conversionFailed(let reason, let exitCode):
            return "safari-web-extension-converter exited with code \(exitCode). Details: \(reason)"
        case .invalidManifest(let reason):
            return reason
        case .incompatibleAPIs(let apis):
            return "The extension uses Chrome APIs that are not supported in Safari: \(apis.joined(separator: ", "))"
        case .downloadFailed(let reason):
            return reason
        case .unarchiveFailed(let reason):
            return reason
        case .projectBuildFailed(let reason):
            return reason
        case .signingFailed(let reason):
            return reason
        case .appLaunchFailed(let reason):
            return reason
        case .registryError(let reason):
            return reason
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .commandLineToolsMissing:
            return "Run 'xcode-select --install' in Terminal or install Xcode Command Line Tools."
        case .converterMissing:
            return "Ensure Xcode is installed and selected with 'sudo xcode-select -s /Applications/Xcode.app'."
        case .processExecutionFailed:
            return "Check the build logs for specific error details."
        case .conversionFailed:
            return "Inspect the converter output in the log drawer and ensure extension manifest and assets are valid."
        case .invalidManifest:
            return "Ensure the extension contains a valid manifest.json file with manifest_version 2 or 3."
        case .incompatibleAPIs:
            return "You can attempt to proceed anyway, but some features of the extension may not work in Safari."
        case .downloadFailed:
            return "Check your internet connection and verify that the extension ID is valid."
        case .unarchiveFailed:
            return "Ensure the CRX or ZIP file is not corrupted."
        case .projectBuildFailed:
            return "Check the Xcode build output in the log drawer."
        case .signingFailed:
            return "Ensure a Personal Team certificate is available or enable unsigned extensions in Safari's Develop menu."
        case .appLaunchFailed:
            return "Check macOS system permissions and ensure the container app exists."
        case .registryError:
            return "Verify that ~/Library/Application Support/Waystation is writable."
        }
    }
}
