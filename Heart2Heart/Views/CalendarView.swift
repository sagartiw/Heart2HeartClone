//calendarview.swift

import SwiftUI

struct MetricNormalization {
    let min: Double
    let max: Double
    let shouldInvert: Bool
}

struct CalendarView: View {
    @EnvironmentObject private var healthDataProcessor: HealthDataProcessor
    @State private var selectedMetric: DisplayMetric = .healthMetric(.restingHeartRate)
    @State private var currentMonth = Date()
    @State private var dailyValues: [Date: Double] = [:]
    @State private var normalization: MetricNormalization?
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            Color(red: 0.141, green: 0.141, blue: 0.141)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                // Top Bar
                HStack {
                    // Logo
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .padding(.leading)
                    
                    Spacer()
                    
                    // Month Navigation
                    HStack {
                        Text(monthYearString(from: currentMonth))
                            .font(.custom("KulimPark-SemiBold", size: 18))
                            .foregroundColor(.white)  // Add this
                            .padding(.horizontal, 8)
                        
                        Button(action: previousMonth) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.white)  // Add this
                        }
                        
                        Button(action: nextMonth) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.white)  // Add this
                        }
                    }
                    
                    Spacer()
                    
                    //Metric Picker
                    Menu {
                        ForEach([
                            DisplayMetric.healthMetric(.restingHeartRate),
                            DisplayMetric.healthMetric(.steps),
                            DisplayMetric.healthMetric(.activeEnergy),
                            DisplayMetric.healthMetric(.heartRateVariability),
                            DisplayMetric.healthMetric(.exerciseTime),
                            DisplayMetric.healthMetric(.elevatedHeartRateTime),
                            DisplayMetric.bandwidthScore
                        ], id: \.self) { metric in
                            Button {
                                selectedMetric = metric
                            } label: {
                                Text(metric.displayName)
                                    .font(.custom("KulimPark-SemiBold", size: 16))
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedMetric.displayName)
                                .font(.custom("KulimPark-SemiBold", size: 16))
                                .foregroundColor(.white)
                            Image(systemName: "chevron.down")
                                .font(.custom("KulimPark-SemiBold", size: 12))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing)
                }
                .padding(.top)
                .padding(.vertical, 8)
                
                // Error Message
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
                
                // Calendar Content
                ScrollView {
                    VStack {
                        // Day labels
                        HStack {
                            ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                                Text(day)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.top)
                        
                        // Calendar grid
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                            ForEach(daysInMonth(), id: \.self) { date in
                                if let date = date {
                                    DayCell(date: date,
                                            value: dailyValues[date] ?? 0,
                                            metric: selectedMetric,
                                            normalization: normalization)
                                } else {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .onChange(of: selectedMetric) { newValue in
                Task {
                    await loadMonthData()
                }
            }
            .onChange(of: currentMonth) { _ in
                Task {
                    await loadMonthData()
                }
            }
            .onAppear {
                Task {
                    await loadMonthData()
                }
            }
        }
    }
    
    private func previousMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }
    
    private func nextMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
    }
    
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func daysInMonth() -> [Date?] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: currentMonth)!
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        
        let numberOfDays = calendar.component(.day, from: interval.end.addingTimeInterval(-1))
        
        for day in 1...numberOfDays {
            if let date = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)).flatMap({ calendar.date(byAdding: .day, value: day - 1, to: $0) }) {
                days.append(date)
            }
        }
        
        while days.count % 7 != 0 {
            days.append(nil)
        }
        
        return days
    }
    
    private func loadMonthData() async {
        print("Starting loadMonthData")
        dailyValues.removeAll()
        
        await calculateNormalization()
        
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: currentMonth)!
        var date = interval.start
        let today = calendar.startOfDay(for: Date())
        
        while date < interval.end {
            // Skip if date is today or in the future
            if date < today {
                switch selectedMetric {
                case .healthMetric(let metric):
                    do {
                        let value = try await healthDataProcessor.healthManager.getDailyMetric(metric, for: date)
                        dailyValues[date] = value
                    } catch {
                        print("Error fetching metric for \(date): \(error)")
                    }
                case .bandwidthScore:
                    do {
                        let score = try await healthDataProcessor.calculateBandwidthScore(for: date)
                        dailyValues[date] = score
                    } catch {
                        print("Error calculating Bandwidth score for \(date): \(error)")
                    }
                }
            }
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
    }
    
    private func calculateNormalization() async {
        var allValues: [Double] = []
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: currentMonth)!
        var date = interval.start
        let today = calendar.startOfDay(for: Date())
        
        while date < interval.end {
            if date < today {
                switch selectedMetric {
                case .healthMetric(let metric):
                    if let value = try? await healthDataProcessor.healthManager.getDailyMetric(metric, for: date) {
                        allValues.append(value)
                    }
                case .bandwidthScore:
                    if let score = try? await healthDataProcessor.calculateBandwidthScore(for: date) {
                        allValues.append(score)
                    }
                }
            }
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        if !allValues.isEmpty {
            let min = allValues.min() ?? 0
            let max = allValues.max() ?? 100
            
            let shouldInvert = switch selectedMetric {
            case .healthMetric(let metric):
                switch metric {
                case .restingHeartRate, .elevatedHeartRateTime:
                    true
                default:
                    false
                }
            case .bandwidthScore:
                false
            }
            
            normalization = MetricNormalization(
                min: min,
                max: max,
                shouldInvert: shouldInvert
            )
        }
    }}


struct DayCell: View {
    let date: Date
    let value: Double
    let metric: DisplayMetric
    let normalization: MetricNormalization?
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private func normalizedValue() -> Double {
            guard let norm = normalization, norm.max != norm.min else { return 0 }
            let normalized = (value - norm.min) / (norm.max - norm.min)
        if normalized == 0 {
            return 0.01
        }
            return normalized
        
        }
    
    private func colorNormalizedValue() -> Double {
        // Only invert the value for color calculation
        let normalized = normalizedValue()
        return normalization?.shouldInvert == true ? 1 - normalized : normalized
    }
    
    private func circleColor() -> Color {
        let normalized = colorNormalizedValue() // Use inverted value for color
        return Color(
            hue: 0.3333 * normalized,
            saturation: 0.8,
            brightness: 0.8
        )
    }
        
    var body: some View {
        ZStack {
            if isToday {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.custom("KulimPark-SemiBold", size: 14))
            } else {
                if value != 0 {
                    Circle()
                        .trim(from: 0, to: CGFloat(normalizedValue())) // Use non-inverted value for fill
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    circleColor(),
                                    circleColor().darker(by: 0.2)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(
                                lineWidth: 4,
                                lineCap: .round
                            )
                        )
                } else {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                }
                
                VStack {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.custom("KulimPark-SemiBold", size: 8))
                    if value > 0 {
                        Text(formatValue())
                            .font(.custom("KulimPark-SemiBold", size: 8))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func formatValue() -> String {
        switch metric {
        case .healthMetric(let metric):
            switch metric {
            case .steps:
                return String(format: "%.0f", value)
            case .activeEnergy:
                return String(format: "%.0f", value)
            case .heartRateVariability:
                return String(format: "%.1f", value)
            case .exerciseTime:
                return String(format: "%.0f", value)
            case .restingHeartRate:
                return String(format: "%.0f", value)
            case .elevatedHeartRateTime:
                return String(format: "%.0f", value)
            default:
                return String(format: "%.1f", value)
            }
        case .bandwidthScore:
            return String(format: "%.0f", value)
        }
    }
    
    private func maxValue() -> Double {
        switch metric {
        case .healthMetric(let metric):
            switch metric {
            case .steps: return 10000
            case .activeEnergy: return 1000
            case .heartRateVariability: return 100
            case .exerciseTime: return 60
            case .restingHeartRate: return 100
            case .elevatedHeartRateTime: return 60
            default: return 100
            }
        case .bandwidthScore:
            return 1000
        }
    }
}

extension Color {
    func darker(by percentage: CGFloat = 0.2) -> Color {
        let uiColor = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(UIColor(hue: h,
                           saturation: s,
                           brightness: b * (1 - percentage),
                           alpha: a))
    }
}

extension DisplayMetric {
    var displayName: String {
        switch self {
        case .healthMetric(let metric):
            switch metric {
            case .restingHeartRate: return "Resting HR"
            case .steps: return "Steps"
            case .activeEnergy: return "Calories"
            case .heartRateVariability: return "HR Variability"
            case .exerciseTime: return "Exercise"
            case .elevatedHeartRateTime: return "Elevated HR"
            default: return "Unknown"
            }
        case .bandwidthScore:
            return "Bandwidth"
        }
    }
}
