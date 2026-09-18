import AppKit
import Foundation

final class AppLauncher {
    func toggle(app: AppEntry, completion: @escaping (Result<LaunchResult, Error>) -> Void) {
        if isFrontmost(bundleId: app.bundleId) {
            if let running = runningApp(bundleId: app.bundleId) {
                let hidden = running.hide()
                if hidden {
                    completion(.success(.hidden))
                } else {
                    completion(.failure(AppLauncherError.couldNotHide(app.name)))
                }
            } else {
                completion(.failure(AppLauncherError.notRunning(app.name)))
            }
            return
        }
        activate(app: app, completion: completion)
    }

    func hide(app: AppEntry, completion: @escaping (Bool) -> Void) {
        guard let running = runningApp(bundleId: app.bundleId) else { completion(true); return }
        if running.isHidden { completion(true); return }
        _ = running.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if running.isHidden { completion(true); return }
            guard running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) else {
                completion(false)
                return
            }
            // ponytail: fixed activation delay; observe workspace activation if timing varies across Macs.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                _ = running.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    completion(running.isHidden)
                }
            }
        }
    }

    func activate(app: AppEntry, completion: @escaping (Result<LaunchResult, Error>) -> Void) {
        let running = runningApp(bundleId: app.bundleId)
        if running?.isActive == true {
            completion(.success(.launched(refreshedBookmark: nil, resolvedPath: nil)))
            return
        }

        guard let bookmarkData = app.bookmarkData else {
            if let running,
               running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) {
                completion(.success(.launched(refreshedBookmark: nil, resolvedPath: nil)))
            } else {
                completion(.failure(AppLauncherError.authorizationRequired(app.name)))
            }
            return
        }

        let resolved: ResolvedApplication
        do {
            resolved = try resolveApplication(bookmarkData: bookmarkData)
        } catch {
            completion(.failure(error))
            return
        }

        let didStartAccess = resolved.url.startAccessingSecurityScopedResource()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: resolved.url, configuration: configuration) { appInstance, error in
            if didStartAccess {
                resolved.url.stopAccessingSecurityScopedResource()
            }

            if appInstance != nil {
                completion(.success(.launched(
                    refreshedBookmark: resolved.refreshedBookmark,
                    resolvedPath: resolved.url.path
                )))
            } else {
                completion(.failure(AppLauncherError.openFailed(app.name, error)))
            }
        }
    }

    private func resolveApplication(bookmarkData: Data) throws -> ResolvedApplication {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw AppLauncherError.invalidAuthorization(error)
        }

        let refreshedBookmark: Data?
        if isStale {
            do {
                refreshedBookmark = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                throw AppLauncherError.invalidAuthorization(error)
            }
        } else {
            refreshedBookmark = nil
        }

        return ResolvedApplication(url: url, refreshedBookmark: refreshedBookmark)
    }

    private func isFrontmost(bundleId: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId
    }

    private func runningApp(bundleId: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }
}

private struct ResolvedApplication {
    let url: URL
    let refreshedBookmark: Data?
}

private enum AppLauncherError: LocalizedError {
    case authorizationRequired(String)
    case invalidAuthorization(Error)
    case notRunning(String)
    case couldNotHide(String)
    case openFailed(String, Error?)

    var errorDescription: String? {
        switch self {
        case .authorizationRequired(let name):
            return "Access to \(name) is required. Open Settings and choose Grant Access."
        case .invalidAuthorization(let error):
            return "The saved application permission is no longer valid: \(error.localizedDescription)"
        case .notRunning(let name):
            return "\(name) is no longer running."
        case .couldNotHide(let name):
            return "BoltLauncher could not hide \(name)."
        case .openFailed(let name, let error):
            if let error {
                return "BoltLauncher could not open \(name): \(error.localizedDescription)"
            }
            return "BoltLauncher could not open \(name)."
        }
    }
}
