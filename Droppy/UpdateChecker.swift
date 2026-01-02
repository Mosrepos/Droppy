//
//  UpdateChecker.swift
//  Droppy
//
//  Created by Jordy Spruit on 02/01/2026.
//

import Foundation
import AppKit
import Combine

/// Lightweight update checker that uses GitHub releases API
@MainActor
class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    
    /// GitHub repository info
    private let owner = "iordv"
    private let repo = "Droppy"
    
    /// Current app version
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    /// Published properties for UI binding
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var downloadURL: URL?
    @Published var releaseNotes: String?
    @Published var isChecking = false
    
    private init() {}
    
    /// Check for updates from GitHub releases
    func checkForUpdates() async {
        guard !isChecking else { return }
        
        isChecking = true
        defer { isChecking = false }
        
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("UpdateChecker: Failed to fetch releases")
                return
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                print("UpdateChecker: Invalid response format")
                return
            }
            
            // Parse version (remove 'v' prefix if present)
            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            
            // Compare versions
            if isNewerVersion(remoteVersion, than: currentVersion) {
                latestVersion = remoteVersion
                releaseNotes = json["body"] as? String
                
                // Find DMG download URL from assets
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.lowercased().hasSuffix(".dmg"),
                           let urlString = asset["browser_download_url"] as? String,
                           let assetURL = URL(string: urlString) {
                            downloadURL = assetURL
                            break
                        }
                    }
                }
                
                updateAvailable = true
                print("UpdateChecker: Update available! \(currentVersion) → \(remoteVersion)")
            } else {
                updateAvailable = false
                print("UpdateChecker: App is up to date (\(currentVersion))")
            }
            
        } catch {
            print("UpdateChecker: Error checking for updates: \(error)")
        }
    }
    
    /// Compare version strings (supports semantic versioning)
    private func isNewerVersion(_ remote: String, than current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(remoteParts.count, currentParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            
            if r > c { return true }
            if r < c { return false }
        }
        
        return false
    }
    
    /// Show update alert to user
    func showUpdateAlert() {
        guard updateAvailable, let version = latestVersion else { return }
        
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Droppy \(version) is available. You are currently using \(currentVersion)."
        
        if releaseNotes != nil {
            alert.informativeText += "\n\nWhat's new:\n\(releaseNotes!.prefix(200))..."
        }
        
        alert.informativeText += "\n\nThe app will update and restart automatically."
        
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update & Restart")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            if let url = downloadURL {
                AutoUpdater.shared.installUpdate(from: url)
            }
        }
    }
    
    // Removed old update methods as they are replaced by AutoUpdater
    
    /// Check for updates and always show feedback to user
    func checkAndNotify() {
        Task {
            await checkForUpdates()
            if updateAvailable {
                showUpdateAlert()
            } else {
                showUpToDateAlert()
            }
        }
    }
    
    /// Show alert that app is up to date
    func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "Droppy is up to date!"
        alert.informativeText = "You're running the latest version (\(currentVersion))."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
