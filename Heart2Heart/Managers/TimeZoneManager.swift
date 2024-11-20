//Managers/TimeZoneManager.swift

import Foundation
import FirebaseFirestore

class TimeZoneManager: ObservableObject {
    @Published private(set) var currentTimeZone: TimeZone
    private let db = Firestore.firestore()
    private let authManager: AuthenticationManager
    
    init(authManager: AuthenticationManager) {
        self.authManager = authManager
        self.currentTimeZone = TimeZone.current
        setupTimeZoneMonitoring()
    }
    
    private func setupTimeZoneMonitoring() {
        // Monitor for time zone changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timeZoneDidChange),
            name: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil
        )
        
        // Update time zone on app launch
        updateTimeZone()
    }
    
    @objc private func timeZoneDidChange() {
        updateTimeZone()
    }
    
    private func updateTimeZone() {
        let newTimeZone = TimeZone.current
        if newTimeZone != currentTimeZone {
            currentTimeZone = newTimeZone
            Task {
                await updateTimeZoneInFirestore()
            }
        }
    }
    
    private func updateTimeZoneInFirestore() async {
        guard let userId = authManager.user?.uid else { return }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "timeZone": currentTimeZone.identifier,
                "timeZoneOffset": currentTimeZone.secondsFromGMT()
            ])
        } catch {
            print("Error updating time zone in Firestore: \(error)")
        }
    }
}
