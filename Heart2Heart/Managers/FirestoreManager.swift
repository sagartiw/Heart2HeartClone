
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
    
    func getUserData(userId: String) async throws -> (partnerId: String?, name: String?) {
        guard !userId.isEmpty else {
            throw FirestoreError.invalidUserId
        }
        
        let document = try await db.collection("users")
            .document(userId)
            .getDocument()
        
        let data = document.data()
        let partnerId = data?["pairedWith"] as? String
        let name = data?["name"] as? String
        
        return (partnerId, name)
    }
    func getComputedData(userId: String, metric: ComputedMetric, date: Date) async throws -> Double? {
            do {
                let dateString = dateFormatter.string(from: date)
                let docRef = db.collection("users")
                    .document(userId)
                    .collection("computedData")
                    .document(dateString)
                
                let document = try await docRef.getDocument()
                if document.exists,
                   let data = document.data(),
                   let metricData = data[metric.firestoreKey] as? Double {
                    return metricData
                }
                return nil
            } catch {
                throw FirestoreError.unknown(error)
            }
        }
        
        func storeComputedData(userId: String, metric: ComputedMetric, date: Date, value: Double) async throws {
            do {
                let dateString = dateFormatter.string(from: date)
                let docRef = db.collection("users")
                    .document(userId)
                    .collection("computedData")
                    .document(dateString)
                
                try await docRef.setData([
                    metric.firestoreKey: value,
                    "timestamp": FieldValue.serverTimestamp()
                ], merge: true)
            } catch {
                throw FirestoreError.unknown(error)
            }
        }
    
    func getHealthData(userId: String, metric: HealthMetric, date: Date) async throws -> Double? {
            do {
                let dateString = dateFormatter.string(from: date)
                let docRef = db.collection("users")
                    .document(userId)
                    .collection("healthData")
                    .document(dateString)
                
                let document = try await docRef.getDocument()
                if document.exists,
                   let data = document.data(),
                   let metricData = data[metric.firestoreKey] as? Double {
                    return metricData
                }
                return nil
            } catch {
                throw FirestoreError.unknown(error)
            }
        }
        
        func storeHealthData(userId: String, metric: HealthMetric, date: Date, value: Double) async throws {
            do {
                let dateString = dateFormatter.string(from: date)
                let docRef = db.collection("users")
                    .document(userId)
                    .collection("healthData")
                    .document(dateString)
                
                try await docRef.setData([
                    metric.firestoreKey: value,
                    "timestamp": FieldValue.serverTimestamp()
                ], merge: true)
            } catch {
                throw FirestoreError.unknown(error)
            }
        }
    
    func getComputedData(userId: String, metric: HealthMetric, date: Date) async throws -> Double? {
            do {
                let dateString = dateFormatter.string(from: date)
                let docRef = db.collection("users")
                    .document(userId)
                    .collection("computedData")
                    .document(dateString)
                
                let document = try await docRef.getDocument()
                if document.exists,
                   let data = document.data(),
                   let metricData = data[metric.firestoreKey] as? Double {
                    return metricData
                }
                return nil
            } catch {
                throw FirestoreError.unknown(error)
            }
        }
        
        func storeComputedData(userId: String, metric: HealthMetric, date: Date, value: Double) async throws {
            do {
                let dateString = dateFormatter.string(from: date)
                let docRef = db.collection("users")
                    .document(userId)
                    .collection("computedData")
                    .document(dateString)
                
                try await docRef.setData([
                    metric.firestoreKey: value,
                    "timestamp": FieldValue.serverTimestamp()
                ], merge: true)
            } catch {
                throw FirestoreError.unknown(error)
            }
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
        case .elevatedHeartRateTime:
            return "elevatedHeartRateTime"
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

extension FirestoreManager {
    func storeSleepMetrics(userId: String, date: Date, metrics: SleepMetrics) async throws {
        do {
            let dateString = dateFormatter.string(from: date)
            let docRef = db.collection("users")
                .document(userId)
                .collection("healthData")
                .document(dateString)
            
            try await docRef.setData([
                "sleepTime": metrics.sleepTime,
                "timestamp": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            throw FirestoreError.unknown(error)
        }
    }
    
    func getSleepMetrics(userId: String, date: Date) async throws -> SleepMetrics? {
        do {
            let dateString = dateFormatter.string(from: date)
            let docRef = db.collection("users")
                .document(userId)
                .collection("healthData")
                .document(dateString)
            
            let document = try await docRef.getDocument()
            if document.exists,
               let data = document.data(),
               let sleepTime = data["sleepTime"] as? TimeInterval {
                // Return SleepMetrics with 0 for inBedTime since we're not caching it
                return SleepMetrics(sleepTime: sleepTime, inBedTime: 0)
            }
            return nil
        } catch {
            throw FirestoreError.unknown(error)
        }
    }
}
