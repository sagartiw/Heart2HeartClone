
//  Managers/FirestoreManager.swift

import FirebaseFirestore

enum FirestoreError: Error {
    case insufficientPermissions
    case invalidData
    case invalidUserId
    case unknown(Error)
}

class FirestoreManager {
    private let db = Firestore.firestore()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    func getPartnerData(userId: String) async throws -> (partnerId: String?, name: String?) {
        guard !userId.isEmpty else {
            throw FirestoreError.invalidUserId
        }
        
        let document = try await db.collection("users")
            .document(userId)
            .getDocument()
        
        let partnerId = document.data()?["pairedWith"] as? String
        
        // If there's a partnerId, fetch their name from their document
        var partnerName: String? = nil
        if let partnerId = partnerId {
            let partnerDoc = try await db.collection("users")
                .document(partnerId)
                .getDocument()
            partnerName = partnerDoc.data()?["name"] as? String
        }
        
        return (partnerId, partnerName)
    }
    
    // Generic method to get data for any metric type
    private func getData<T: StorableMetric>(userId: String, metric: T, date: Date, collection: String) async throws -> Double? {
        let dateString = dateFormatter.string(from: date)
        let docRef = db.collection("users")
            .document(userId)
            .collection(collection)
            .document(dateString)
        
        let document = try await docRef.getDocument()
        return document.exists ? document.data()?[metric.firestoreKey] as? Double : nil
    }
    
    // Generic method to store data for any metric type
    private func storeData<T: StorableMetric>(userId: String, metric: T, date: Date, value: Double, collection: String) async throws {
        let dateString = dateFormatter.string(from: date)
        let docRef = db.collection("users")
            .document(userId)
            .collection(collection)
            .document(dateString)

        try await docRef.setData([
            metric.firestoreKey: value,
            "timestamp": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    // Public methods using the generic helpers
    func getHealthData(userId: String, metric: HealthMetric, date: Date) async throws -> Double? {
        try await getData(userId: userId, metric: metric, date: date, collection: "healthData")
    }
    
    func storeHealthData(userId: String, metric: HealthMetric, date: Date, value: Double) async throws {
        try await storeData(userId: userId, metric: metric, date: date, value: value, collection: "healthData")
    }
    
    func getComputedData(userId: String, metric: ComputedMetric, date: Date) async throws -> Double? {
        try await getData(userId: userId, metric: metric, date: date, collection: "computedData")
    }
    
    func storeComputedData(userId: String, metric: ComputedMetric, date: Date, value: Double) async throws {
        try await storeData(userId: userId, metric: metric, date: date, value: value, collection: "computedData")
    }
    
    // Sleep metrics methods
    func storeSleepMetrics(userId: String, date: Date, metrics: SleepMetrics) async throws {
        let dateString = dateFormatter.string(from: date)
        let docRef = db.collection("users")
            .document(userId)
            .collection("healthData")
            .document(dateString)
        
        try await docRef.setData([
            "sleepTime": metrics.sleepTime,
            "timestamp": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func getSleepMetrics(userId: String, date: Date) async throws -> SleepMetrics? {
        let dateString = dateFormatter.string(from: date)
        let docRef = db.collection("users")
            .document(userId)
            .collection("healthData")
            .document(dateString)
        
        let document = try await docRef.getDocument()
        guard let sleepTime = document.data()?["sleepTime"] as? TimeInterval else { return nil }
        return SleepMetrics(sleepTime: sleepTime, inBedTime: 0)
    }
    
    
}
protocol StorableMetric {
    var firestoreKey: String { get }
    var isComputedMetric: Bool { get }
    var shouldCache: Bool { get }
}

enum ComputedMetric: String, StorableMetric {
    case bandwidth
    case heartRateComponent
    case exerciseComponent
    case sleepComponent
    case elevatedHeartRateTime
    
    var firestoreKey: String {
        rawValue
    }
    
    var isComputedMetric: Bool {
        true
    }
    
    var shouldCache: Bool {
        true
    }
}

extension HealthMetric {
    var firestoreKey: String {
        switch self {
        case .restingHeartRate:
            return "rhr"
        case .heartRateVariability:
            return "hrv"
        case .activeEnergy:
            return "activeEnergy"
        case .exerciseTime:
            return "exerciseMinutes"
        default:
            return ""
        }
    }
    
    var isComputedMetric: Bool {
        switch self {
        case .elevatedHeartRateTime:
            return true
        default:
            return false
        }
    }
    
    var shouldCache: Bool {
        switch self {
        case .restingHeartRate, .heartRateVariability, .activeEnergy, .exerciseTime:
            return true
        case .elevatedHeartRateTime:
            return true
        default:
            return false
        }
    }
}
