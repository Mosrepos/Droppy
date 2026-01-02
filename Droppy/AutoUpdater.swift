//
//  AutoUpdater.swift
//  Droppy
//
//  Created by Jordy Spruit on 02/01/2026.
//

import Foundation
import AppKit

/// Handles downloading and installing app updates
class AutoUpdater {
    static let shared = AutoUpdater()
    
    private init() {}
    
    /// Downloads and installs the update from the given URL
    func installUpdate(from url: URL) {
        Task {
            // 1. Download DMG
            guard let dmgURL = await downloadDMG(from: url) else {
                return
            }
            
            // 2. Install and Restart
            do {
                try installAndRestart(dmgPath: dmgURL.path)
            } catch {
                print("AutoUpdater: Installation failed: \(error)")
                await MainActor.run {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }
    
    private func downloadDMG(from url: URL) async -> URL? {
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent("DroppyUpdate.dmg")
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: destinationURL)
            return destinationURL
        } catch {
            print("AutoUpdater: Download failed: \(error)")
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Update Failed"
                alert.informativeText = "Could not download the update. Please try again later."
                alert.runModal()
            }
            return nil
        }
    }
    
    private func installAndRestart(dmgPath: String) throws {
        // Create a temporary install script
        let scriptPath = FileManager.default.temporaryDirectory.appendingPathComponent("install_droppy.sh").path
        let appPath = Bundle.main.bundlePath
        let appName = "Droppy.app"
        
        let script = """
        #!/bin/bash
        
        # Wait for app to close
        sleep 2
        
        # Mount DMG
        echo "Mounting DMG..."
        hdiutil attach "\(dmgPath)" -nobrowse -mountpoint /Volumes/DroppyUpdate
        
        # Copy new app
        echo "Installing..."
        rm -rf "\(appPath)"
        cp -R "/Volumes/DroppyUpdate/\(appName)" "\(appPath)"
        
        # Cleanup
        hdiutil detach /Volumes/DroppyUpdate
        rm -f "\(dmgPath)"
        rm -f "$0" # Delete script
        
        # Relaunch
        echo "Relaunching..."
        open -n "\(appPath)"
        """
        
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        
        // Make executable
        var attributes = [FileAttributeKey : Any]()
        attributes[.posixPermissions] = 0o755
        try FileManager.default.setAttributes(attributes, ofItemAtPath: scriptPath)
        
        // Run script in background
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = [scriptPath]
        process.launch()
        
        // Terminate current app
        NSApplication.shared.terminate(nil)
    }
}
