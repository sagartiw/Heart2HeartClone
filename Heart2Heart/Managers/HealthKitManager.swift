//Managers/HealthkitManager

import HealthKit

// MARK: - Supporting Types
private extension Date {
    var dayInterval: (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: self)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }
}

enum HealthKitError: Error {
    case notAvailable
    case authorizationFailed(Error)
    case noData
}

enum HealthMetric: StorableMetric {
    case restingHeartRate
    case steps
    case activeEnergy
    case heartRateVariability
    case exerciseTime
    case elevatedHeartRateTime
    case heartRate
    case hrv
    
    
    var quantityType: HKQuantityType {
        switch self {
        case .steps:
            return .quantityType(forIdentifier: .stepCount)!
        case .activeEnergy:
            return .quantityType(forIdentifier: .activeEnergyBurned)!
        case .exerciseTime:
            return .quantityType(forIdentifier: .appleExerciseTime)!
        case .heartRate, .elevatedHeartRateTime:
            return .quantityType(forIdentifier: .heartRate)!
        case .heartRateVariability, .hrv:
            return .quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        case .restingHeartRate:
            return .quantityType(forIdentifier: .restingHeartRate)!
        }
    }
    
    var unit: HKUnit {
        switch self {
        case .steps:
            return .count()
        case .activeEnergy:
            return .kilocalorie()
        case .exerciseTime:
            return .minute()
        case .heartRate, .elevatedHeartRateTime:
            return .count().unitDivided(by: .minute())
        case .heartRateVariability, .hrv:
            return .secondUnit(with: .milli)
        case .restingHeartRate:
            return .count().unitDivided(by: .minute())
        }
    }
}



struct SleepMetrics: StorableMetric {
    let sleepTime: TimeInterval
    let inBedTime: TimeInterval
    
    // Instead of switch case, just return a fixed key since this is a struct
    var firestoreKey: String {
        return "sleepMetrics"
    }
    
    var isComputedMetric: Bool { false }
    var shouldCache: Bool { true }
}

// MARK: - HealthKitManager
class HealthKitManager {
    private let healthStore = HKHealthStore()
    private let firestoreManager: FirestoreManager
    private let authManager: AuthenticationManager
    
    init(firestoreManager: FirestoreManager, authManager: AuthenticationManager) {
        self.firestoreManager = firestoreManager
        self.authManager = authManager
    }
    
    // Helper property to safely get userId
    private var userId: String? {
        authManager.user?.uid
    }
    
    func checkAuthorizationStatus() async -> Bool {
        for type in healthTypes {
            let status = healthStore.authorizationStatus(for: type)
            
            switch status {
            case .notDetermined:
                return false
            case .sharingDenied:
                // This is OK for read-only access
                continue
            case .sharingAuthorized:
                // This is OK for read-only access
                continue
            @unknown default:
                return false
            }
        }
        return true
    }
    
    func requestAuthorization() async throws -> Bool {
        
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: healthTypes)
            
            for type in healthTypes {
                if let sampleType = type as? HKSampleType {
                    try await enableBackgroundDelivery(for: sampleType)
                }
            }
            
            // Add detailed status checking for each type
            for type in healthTypes {
                let status = healthStore.authorizationStatus(for: type)
            }
            
            let authStatus = await checkAuthorizationStatus()
            
            return authStatus
            
        } catch {
            print("❌ Healthkit Authorization failed with error: \(error)")
            throw HealthKitError.authorizationFailed(error)
        }
    }
    
    private func enableBackgroundDelivery(for type: HKSampleType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "HealthKit", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to enable background delivery"]))
                }
            }
        }
    }
    
    
    
    private let healthTypes: Set<HKObjectType> = Set([
        .heartRate, .heartRateVariabilitySDNN, .restingHeartRate,
        .stepCount, .activeEnergyBurned, .appleExerciseTime
    ].compactMap { HKQuantityType.quantityType(forIdentifier: $0) } + [
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    ])
    
    
    // MARK: - Generic Data Fetching
    private func fetchData<T: HKSample>(
        type: HKSampleType,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: startDate, end: endDate),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [.init(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [T] ?? [])
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Metrics
    func getDailyMetric(_ metric: HealthMetric, for date: Date) async throws -> Double {
        guard let userId = userId else {
            throw HealthKitError.notAvailable
        }
        
        // Skip cache if the date is today
        let isToday = Calendar.current.isDateInToday(date)
        
        // Check Firestore only if metric should be cached AND it's not today
        if metric.shouldCache && !isToday {
            if let cachedValue = try await firestoreManager.getHealthData(userId: userId, metric: metric, date: date) {
                return cachedValue
            }
        }
        
        // Get from HealthKit
        let value = try await fetchFromHealthKit(metric, for: date)
        
        
        try await firestoreManager.storeHealthData(userId: userId, metric: metric, date: date, value: value)
        
        return value
    }
    
    private func fetchFromHealthKit(_ metric: HealthMetric, for date: Date) async throws -> Double {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        
        // Choose statistics option based on metric type
        let options: HKStatisticsOptions
        switch metric.quantityType.identifier {
        case HKQuantityTypeIdentifier.stepCount.rawValue,
            HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            HKQuantityTypeIdentifier.appleExerciseTime.rawValue:
            options = .cumulativeSum
        case HKQuantityTypeIdentifier.heartRate.rawValue,
            HKQuantityTypeIdentifier.restingHeartRate.rawValue,
            HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            options = .discreteAverage
        default:
            options = .cumulativeSum
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: metric.quantityType,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let value: Double
                switch options {
                case .cumulativeSum:
                    value = statistics?.sumQuantity()?.doubleValue(for: metric.unit) ?? 0
                case .discreteAverage:
                    value = statistics?.averageQuantity()?.doubleValue(for: metric.unit) ?? 0
                default:
                    value = 0
                }
                
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
    
    func getAverageMetric(_ metric: HealthMetric, for date: Date) async throws -> Double {
        let total = try await getDailyMetric(metric, for: date)
        let samples: [HKQuantitySample] = try await fetchData(
            type: metric.quantityType,
            from: date.dayInterval.start,
            to: date.dayInterval.end
        )
        
        return samples.isEmpty ? 0 : total / Double(samples.count)
    }
    
    // MARK: - Sleep Analysis
    func getSleepMetrics(for date: Date) async throws -> SleepMetrics {
        guard let userId = userId else {
            throw HealthKitError.notAvailable
        }
        
        let isToday = Calendar.current.isDateInToday(date)
        
        // Check Firestore cache only if it's not today
        if !isToday {
            if let cachedMetrics = try await firestoreManager.getSleepMetrics(userId: userId, date: date) {
                return cachedMetrics
            }
        }
        
        // If not cached, fetch from HealthKit
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let (start, end) = date.dayInterval
        
        let samples: [HKCategorySample] = try await fetchData(type: sleepType, from: start, to: end)
        
        var sleepTime: TimeInterval = 0
        var inBedTime: TimeInterval = 0
        
        for sample in samples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            
            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                sleepTime += duration
                inBedTime += duration
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                inBedTime += duration
            default:
                break
            }
        }
        
        let metrics = SleepMetrics(sleepTime: sleepTime, inBedTime: inBedTime)
        // Cache the metrics in Firestore
        try await firestoreManager.storeSleepMetrics(userId: userId, date: date, metrics: metrics)
        
        return metrics
    }
    
    // MARK: - Heart Rate Analysis
    func getTimeAboveHeartRatePercentage(date: Date, percentage: Double) async throws -> TimeInterval {
        guard let userId = userId else {
            throw HealthKitError.notAvailable
        }
        let isToday = Calendar.current.isDateInToday(date)
        
        // Check Firestore cache only if it's not today
        if !isToday {
            // First check Firestore cache
            if let cachedValue = try await firestoreManager.getComputedData(
                userId: userId,
                metric: .elevatedHeartRateTime,
                date: date
            ) {
                return cachedValue
            }
        }
        
        let (start, end) = date.dayInterval
        
        // Fetch heart rate samples
        let heartRateSamples: [HKQuantitySample] = try await fetchData(
            type: HealthMetric.heartRate.quantityType,
            from: start,
            to: end
        ).sorted { $0.startDate < $1.startDate }
        
        // Fetch exercise samples
        let exerciseSamples: [HKQuantitySample] = try await fetchData(
            type: HealthMetric.exerciseTime.quantityType,
            from: start,
            to: end
        )
        
        guard let maxHR = heartRateSamples.map({ $0.quantity.doubleValue(for: HealthMetric.heartRate.unit) }).max()
        else { return 0 }
        
        let targetHR = maxHR * (percentage / 100.0)
        var elevatedTimeTotal: TimeInterval = 0
        
        // Create a set of exercise time intervals
        let exerciseIntervals: [(start: Date, end: Date)] = exerciseSamples.map {
            (start: $0.startDate, end: $0.endDate)
        }
        
        // Helper function to check if a time is during exercise
        func isDuringExercise(_ date: Date) -> Bool {
            exerciseIntervals.contains { interval in
                date >= interval.start && date <= interval.end
            }
        }
        
        for i in 0..<(heartRateSamples.count - 1) {
            let currentSample = heartRateSamples[i]
            let nextSample = heartRateSamples[i + 1]
            
            // Check if heart rate is elevated and not during exercise
            if currentSample.quantity.doubleValue(for: HealthMetric.heartRate.unit) > targetHR &&
                !isDuringExercise(currentSample.startDate) {
                elevatedTimeTotal += nextSample.startDate.timeIntervalSince(currentSample.startDate)
            }
        }
        
        // Handle the last sample
        if let lastSample = heartRateSamples.last,
           lastSample.quantity.doubleValue(for: HealthMetric.heartRate.unit) > targetHR,
           !isDuringExercise(lastSample.startDate) {
            elevatedTimeTotal += (end.timeIntervalSince(start)) / Double(heartRateSamples.count)
        }
        
        try await firestoreManager.storeComputedData(
            userId: userId,
            metric: .elevatedHeartRateTime,
            date: date,
            value: elevatedTimeTotal
        )
        
        return elevatedTimeTotal
    }
}
// MARK: - Convenience Methods
extension HealthKitManager {
    func getDailySteps(for date: Date) async throws -> Double {
        try await getDailyMetric(.steps, for: date)
    }
    
    func getDailyActiveEnergy(for date: Date) async throws -> Double {
        try await getDailyMetric(.activeEnergy, for: date)
    }
    
    func getDailyExerciseTime(for date: Date) async throws -> Double {
        try await getDailyMetric(.exerciseTime, for: date)
    }
    
    func getAverageHeartRate(for date: Date) async throws -> Double {
        try await getAverageMetric(.heartRate, for: date)
    }
    
    func getAverageHRV(for date: Date) async throws -> Double {
        try await getAverageMetric(.hrv, for: date)
    }
}
