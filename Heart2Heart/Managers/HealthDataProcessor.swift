//healthdata processor

import Foundation
import Combine

@MainActor
final class HealthDataProcessor : ObservableObject {
    let healthManager: HealthKitManager
    private let settingsManager: SettingsManager
    private var cancellables = Set<AnyCancellable>()
    private let firestoreManager: FirestoreManager
    private let authManager: AuthenticationManager

    
    @Published private(set) var currentBandwidthScore: Double = 0
    @Published private(set) var isCalculating = false
    @Published private(set) var lastError: String?
    
    
    
    // MARK: - Constants
    private enum Constants {
        static let baselineSleepHours: Double = 8
        static let elevatedHRPercentage: Double = 70
        static let maxBandwidthScore: Double = 100
        static let secondsInDay: Double = 60 * 3600
    }
    
    private enum BandwidthWeights {
        static let hrv: Double = 30.0
        static let rhr: Double = 20.0
        static let sleep: Double = 0.0//20.0
        static let elevatedHR: Double = 15.0
        static let exercise: Double = -10.0
        static let steps: Double = -5.0
        static let calories: Double = -5.0
    }
    
    // MARK: - Properties
    private struct Metrics: Sendable {
        let hrv: Double
        let rhr: Double
        let sleepTime: TimeInterval
        let elevatedHRTime: TimeInterval
        let totalNonExerciseTime: TimeInterval
        let exerciseMinutes: Double
        let steps: Double
        let caloriesBurned: Double
        
        static func calculateNonExerciseTime(exerciseMinutes: Double) -> TimeInterval {
            Constants.secondsInDay - (exerciseMinutes * 60)
        }
    }
    
    // MARK: - Initialization
    @MainActor
        func initialize() async throws {
            // Check and request HealthKit authorization
            let isAuthorized = try await healthManager.requestAuthorization()
            guard isAuthorized else {
                throw HealthKitError.authorizationFailed(NSError(domain: "HealthKit", code: 0, userInfo: [NSLocalizedDescriptionKey: "Authorization denied"]))
            }
        }
    
    init(settingsManager: SettingsManager, authManager: AuthenticationManager) {
        self.settingsManager = settingsManager
        self.firestoreManager = FirestoreManager()
        self.authManager = authManager
        self.healthManager = HealthKitManager(
            firestoreManager: self.firestoreManager,
            authManager: authManager
        )
    }

    // MARK: - Public Methods
    func calculateWindowAverage(for metric: HealthMetric, days: Int) async -> Double {
        let values = await fetchMetricValues(for: metric, days: days)
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    
    func calculateBandwidthScore(for date: Date) async throws -> Double {
        guard let userId = authManager.user?.uid else {
            throw AuthError.userNotAuthenticated
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        // Check for cached final score
        if let cachedScore = try await firestoreManager.getComputedData(
            userId: userId,
            metric: .bandwidth,
            date: startOfDay
        ) {
            return cachedScore
        }
        let weights = settingsManager.settings
        var components: [Double] = []

        // Calculate heart rate component
        if weights.isHeartRateEnabled {
            let heartRateScore = try await calculateHeartRateComponent(
                for: startOfDay,
                userId: userId
            )
            components.append(heartRateScore * weights.mainWeights["heartRate"]!)
        }
        
        // Calculate exercise component
        if weights.isExerciseEnabled {
            let exerciseScore = try await calculateExerciseComponent(
                for: startOfDay,
                userId: userId
            )
            components.append(exerciseScore * weights.mainWeights["exercise"]!)
        }
        

        // Calculate sleep component
        if weights.isSleepEnabled {
            let sleepScore = try await calculateSleepComponent(
                for: startOfDay,
                userId: userId
            )
            components.append(sleepScore * weights.mainWeights["sleep"]!)
        }
        
        let finalScore = components.reduce(0, +)/100.0
        
        // Cache the final score
        try await firestoreManager.storeComputedData(
                userId: userId,
                metric: .bandwidth,
                date: startOfDay,
                value: finalScore
            )
            
            return finalScore
    }
    
    private enum AuthError: Error {
            case userNotAuthenticated
        }

    private func calculateHeartRateComponent(for date: Date, userId: String) async throws -> Double {
        let calendar = Calendar.current
        let weights = settingsManager.settings.recentDaysWeights
        
        try await Task.sleep(for: .seconds(1))


        // Check cache first
        if let cached = try await firestoreManager.getComputedData(
            userId: userId,
            metric: .heartRateComponent,
            date: date
        ) {
            return cached
        }

        var weightedSum = 0.0
        for daysAgo in 0...2 {
            let dayDate = calendar.date(byAdding: .day, value: -daysAgo, to: date) ?? date
            let metrics = try await getCurrentMetrics(for: dayDate)
            let baseline = try await getBaselineMetrics()

            let dayWeight = daysAgo == 0 ? weights["currentDay"] :
                           daysAgo == 1 ? weights["yesterday"] :
                                        weights["twoDaysAgo"]
            
            let hrvComponent = baseline.hrv != 0 ? ((baseline.hrv - metrics.hrv) / baseline.hrv) : 0
            let rhrComponent = baseline.rhr != 0 ? ((metrics.rhr - baseline.rhr) / baseline.rhr) : 0
            let elevatedComponent = metrics.totalNonExerciseTime != 0 ?
                (metrics.elevatedHRTime / metrics.totalNonExerciseTime) : 0
            
            let dayScore = (hrvComponent * (settingsManager.settings.heartRateWeights["variability"] ?? 0) +
                            rhrComponent * (settingsManager.settings.heartRateWeights["resting"] ?? 0) +
                            elevatedComponent * (settingsManager.settings.heartRateWeights["elevated"] ?? 0)) *
                           (dayWeight ?? 0) / 100.0
            
            weightedSum += dayScore
        }
        
        // Cache the component score
        try await firestoreManager.storeComputedData(
            userId: userId,
            metric: .heartRateComponent,
            date: date,
            value: weightedSum
        )
        
        return weightedSum
    }
    
    private func calculateExerciseComponent(for date: Date, userId: String) async throws -> Double {
        let calendar = Calendar.current
        let weights = settingsManager.settings.recentDaysWeights
        
        // Check cache first
        if let cached = try await firestoreManager.getComputedData(
            userId: userId,
            metric: .exerciseComponent,
            date: date
        ) {
            return cached
        }
        
        var weightedSum = 0.0
        for daysAgo in 0...2 {
            let dayDate = calendar.date(byAdding: .day, value: -daysAgo, to: date) ?? date
            let metrics = try await getCurrentMetrics(for: dayDate)
            let baseline = try await getBaselineMetrics()
            
            let dayWeight = daysAgo == 0 ? weights["currentDay"] :
                           daysAgo == 1 ? weights["yesterday"] :
                                        weights["twoDaysAgo"]
            
            let exerciseMinutesComponent = baseline.exerciseMinutes != 0 ?
                (baseline.exerciseMinutes - metrics.exerciseMinutes) / baseline.exerciseMinutes : 0
            
            let stepsComponent = baseline.steps != 0 ?
                (baseline.steps - metrics.steps) / baseline.steps : 0
            
            let caloriesComponent = baseline.caloriesBurned != 0 ?
                (baseline.caloriesBurned - metrics.caloriesBurned) / baseline.caloriesBurned : 0
            
            let dayScore = (exerciseMinutesComponent * (settingsManager.settings.exerciseWeights["minutes"] ?? 0) +
                            stepsComponent * (settingsManager.settings.exerciseWeights["steps"] ?? 0) +
                            caloriesComponent * (settingsManager.settings.exerciseWeights["calories"] ?? 0)) *
                           (dayWeight ?? 0) / 100.0
            
            weightedSum += dayScore
        }
        
        // Cache the component score
        try await firestoreManager.storeComputedData(
            userId: userId,
            metric: .exerciseComponent,
            date: date,
            value: weightedSum
        )
        
        return weightedSum
    }

    private func calculateSleepComponent(for date: Date, userId: String) async throws -> Double {
        let calendar = Calendar.current
        let weights = settingsManager.settings.recentDaysWeights
        
        // Check cache first
        if let cached = try await firestoreManager.getComputedData(
            userId: userId,
            metric: .sleepComponent,
            date: date
        ) {
            return cached
        }
        
        var weightedSum = 0.0
        for daysAgo in 0...2 {
            let dayDate = calendar.date(byAdding: .day, value: -daysAgo, to: date) ?? date
            let metrics = try await getCurrentMetrics(for: dayDate)
            
            let dayWeight = daysAgo == 0 ? weights["currentDay"] :
                           daysAgo == 1 ? weights["yesterday"] :
                                        weights["twoDaysAgo"]
            
            // Calculate sleep deviation from baseline (8 hours)
            let sleepDeviation = ((Constants.baselineSleepHours * 3600 - metrics.sleepTime) /
                                 (Constants.baselineSleepHours * 3600))
            
            let dayScore = sleepDeviation * (dayWeight ?? 0) / 100.0
            weightedSum += dayScore
        }
        
        // Cache the component score
        try await firestoreManager.storeComputedData(
            userId: userId,
            metric: .sleepComponent,
            date: date,
            value: weightedSum
        )
        
        return weightedSum
    }
    
    private func calculateAverageElevatedHRTime(days: Int) async throws -> TimeInterval {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var totalTime: TimeInterval = 0
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            totalTime += try await healthManager.getTimeAboveHeartRatePercentage(
                date: date,
                percentage: Constants.elevatedHRPercentage
            )
        }
        
        return totalTime / Double(days)
    }
    
    
    private func getBaselineMetrics() async throws -> Metrics {
        let days = settingsManager.settings.averagingPeriodDays
        
        async let hrv = calculateWindowAverage(for: .heartRateVariability, days: days)
        async let rhr = calculateWindowAverage(for: .restingHeartRate, days: days)
        async let exercise = calculateWindowAverage(for: .exerciseTime, days: days)
        async let steps = calculateWindowAverage(for: .steps, days: days)
        async let calories = calculateWindowAverage(for: .activeEnergy, days: days)
        async let elevatedHRTime = try calculateAverageElevatedHRTime(days: days)
        
        let (hrvValue, rhrValue, exerciseValue, stepsValue, caloriesValue, elevatedHRValue) =
            await (hrv, rhr, exercise, steps, calories, try elevatedHRTime)
        
        return Metrics(
            hrv: hrvValue,
            rhr: rhrValue,
            sleepTime: Constants.baselineSleepHours * 3600,
            elevatedHRTime: elevatedHRValue,
            totalNonExerciseTime: Metrics.calculateNonExerciseTime(exerciseMinutes: exerciseValue),
            exerciseMinutes: exerciseValue,
            steps: stepsValue,
            caloriesBurned: caloriesValue
        )
    }

    private func getCurrentMetrics(for date: Date) async throws -> Metrics {
        async let hrv = healthManager.getAverageHRV(for: date)
        async let rhr = healthManager.getDailyMetric(.restingHeartRate, for: date)
        async let sleepMetrics = healthManager.getSleepMetrics(for: date)
        async let exercise = healthManager.getDailyExerciseTime(for: date)
        async let steps = healthManager.getDailySteps(for: date)
        async let calories = healthManager.getDailyActiveEnergy(for: date)
        async let elevatedHRTime = healthManager.getTimeAboveHeartRatePercentage(
            date: date,
            percentage: Constants.elevatedHRPercentage
        )
                        
        let (hrvValue, rhrValue, sleep, exerciseValue, stepsValue, caloriesValue, elevatedHR) =
            try await (hrv, rhr, sleepMetrics, exercise, steps, calories, elevatedHRTime)
        
        
        return Metrics(
            hrv: hrvValue,
            rhr: rhrValue,
            sleepTime: sleep.sleepTime,
            elevatedHRTime: elevatedHR,
            totalNonExerciseTime: Metrics.calculateNonExerciseTime(exerciseMinutes: exerciseValue),
            exerciseMinutes: exerciseValue,
            steps: stepsValue,
            caloriesBurned: caloriesValue
        )
    }
    
    private func fetchMetricValues(for metric: HealthMetric, days: Int) async -> [Double] {

        struct MetricResult: Sendable {
            let value: Double
            let isValid: Bool
        }
        
        return await withTaskGroup(of: MetricResult.self, returning: [Double].self) { @Sendable group -> [Double] in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            for dayOffset in 0..<days {
                group.addTask { [weak self] in
                    guard let self = self,
                          let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                        return MetricResult(value: 0, isValid: false)
                    }
                    do {
                        let value = try await self.healthManager.getDailyMetric(metric, for: date)
                        return MetricResult(value: value, isValid: value > 0)
                    } catch {
                        //print("Error fetching \(metric) for \(date): \(error)")
                        return MetricResult(value: 0, isValid: false)
                    }
                }
            }
            
            var validValues: [Double] = []
            for await result in group {
                if result.isValid {
                    validValues.append(result.value)
                }
            }
            return validValues
        }
    }
    
    private struct AggregateMetrics {
        var hrv: Double = 0
        var rhr: Double = 0
        var exercise: Double = 0
        var steps: Double = 0
        var calories: Double = 0
    }
    
    private func fetchAggregateMetrics(forPast days: Int) async throws -> AggregateMetrics {
            var metrics = AggregateMetrics()
            let calendar = Calendar.current
            let today = Date()
            
            for dayOffset in 0..<days {
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
                
                metrics.hrv += try await healthManager.getAverageHRV(for: date)
                metrics.rhr += try await healthManager.getDailyMetric(.restingHeartRate, for: date)
                metrics.exercise += try await healthManager.getDailyExerciseTime(for: date)
                metrics.steps += try await healthManager.getDailySteps(for: date)
                metrics.calories += try await healthManager.getDailyActiveEnergy(for: date)
            }
            
            return metrics
        }
    
    }





    // MARK: - HealthMetric Extension
    private extension HealthMetric {
        func formattedValue(_ value: Double) -> String {
            switch self {
            case .restingHeartRate:
                return String(format: "%.1f BPM", value)
            case .steps:
                return String(format: "%.0f steps", value)
            case .activeEnergy:
                return String(format: "%.0f calories", value)
            case .heartRateVariability:
                return String(format: "%.1f ms", value)
            case .exerciseTime:
                return String(format: "%.0f minutes", value)
            case .elevatedHeartRateTime:
                return String(format: "%.1f minutes", value)
            default:
                return ""
            }
        }
    }



//MARK: component metric extension
enum componentMetric {
    case heartRateComponent
    case exerciseComponent
    case sleepComponent
    
    var firestoreKey: String {
        switch self {
            case .heartRateComponent: return "heartRateComponent"
            case .exerciseComponent: return "exerciseComponent"
            case .sleepComponent: return "sleepComponent"
        }
    }
}


