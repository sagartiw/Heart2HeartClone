//Managers/DailyTaskManager.swift

import Foundation
import Firebase

class DailyTaskManager: ObservableObject {
    @Published var lastUpdate: Date?
    private var listener: ListenerRegistration?
    
    func startListening() {
        let db = Firestore.firestore()
        
        listener = db.collection("dailyTasks")
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let document = snapshot?.documents.first,
                      let timestamp = document.data()["timestamp"] as? Timestamp else {
                    return
                }
                
                self.lastUpdate = timestamp.dateValue()
                self.handleDailyUpdate(document.data())
            }
    }
    
    func handleDailyUpdate(_ data: [String: Any]) {
        // Handle the daily update here
        // This will be called whenever the Cloud Function executes
        print("Received daily update: \(data)")
        
        // Perform any local app updates needed
    }
    
    deinit {
        listener?.remove()
    }
}
