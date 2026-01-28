import Foundation

class UpdateChecker {
    struct Release: Codable {
        let tag_name: String
        let html_url: String
    }

    struct UpdateInfo {
        let latestVersion: String
        let releaseURL: String
        let isUpdateAvailable: Bool
    }

    static func checkForUpdates(currentVersion: String, completion: @escaping (UpdateInfo?) -> Void) {
        logDebug("Checking for updates (current version: \(currentVersion))")

        DispatchQueue.global(qos: .utility).async {
            guard let url = URL(string: "https://api.github.com/repos/dvdpearson/IsItMe/releases/latest") else {
                logError("Invalid update check URL")
                completion(nil)
                return
            }

            var request = URLRequest(url: url)
            request.setValue("IsItMe/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    logWarning("Update check failed: \(error.localizedDescription)")
                    completion(nil)
                    return
                }

                guard let data = data else {
                    logWarning("Update check returned no data")
                    completion(nil)
                    return
                }

                guard let release = try? JSONDecoder().decode(Release.self, from: data) else {
                    logWarning("Failed to decode update check response")
                    completion(nil)
                    return
                }

                let latestVersion = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                let isUpdateAvailable = compareVersions(current: currentVersion, latest: latestVersion)

                logInfo("Update check complete - latest: \(latestVersion), update available: \(isUpdateAvailable)")

                let updateInfo = UpdateInfo(
                    latestVersion: latestVersion,
                    releaseURL: release.html_url,
                    isUpdateAvailable: isUpdateAvailable
                )

                completion(updateInfo)
            }

            task.resume()
        }
    }

    private static func compareVersions(current: String, latest: String) -> Bool {
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(currentComponents.count, latestComponents.count)

        for i in 0..<maxLength {
            let currentValue = i < currentComponents.count ? currentComponents[i] : 0
            let latestValue = i < latestComponents.count ? latestComponents[i] : 0

            if latestValue > currentValue {
                return true
            }
            if latestValue < currentValue {
                return false
            }
        }

        return false
    }
}
