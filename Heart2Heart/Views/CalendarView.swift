//calendarview.swift

import SwiftUI

struct MetricNormalization {
    let min: Double
    let max: Double
    let shouldInvert: Bool
}

struct CalendarView: View {
    @EnvironmentObject private var healthDataProcessor: HealthDataProcessor
    @EnvironmentObject private var authManager: AuthenticationManager
    private var firestoreManager = FirestoreManager()

    @State private var currentMonth = Date()
    @State private var dailyValues: [Date: Double] = [:]
    @State private var normalization: MetricNormalization?
    @State private var errorMessage: String?
    @State private var selectedDate: Date?
    @State private var components: [String: Double] = [:]


    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.141, green: 0.141, blue: 0.141)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    ScrollView {
                        VStack {
                            HStack {
                                ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                                    Text(day)
                                        .foregroundColor(Color(red:0.894, green: 0.949, blue: 0.839))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.top)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                                ForEach(daysInMonth(), id: \.self) { date in
                                    if let date = date {
                                        DayCell(
                                            date: date,
                                            value: dailyValues[date] ?? 0,
                                            normalization: normalization,
                                            onTap: {
                                                selectedDate = date
                                                Task {
                                                    await loadComponents(for: date)
                                                }
                                            },
                                            isSelected: selectedDate == date
                                        )
                                    } else {
                                        Color.clear
                                            .aspectRatio(1, contentMode: .fit)
                                    }
                                }
                            }
                            .padding()
                        }
                        
                        if let selectedDate = selectedDate, !components.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Components:")
                                    .foregroundColor(Color(red:0.894, green: 0.949, blue: 0.839))
                                    .font(.headline)
                                    .padding(.top)
                                
                                ForEach(Array(components.keys.sorted()), id: \.self) { key in
                                    if let value = components[key] {
                                        HStack {
                                            Text(key == "exerciseComponent" ? "Exercise:" :
                                                 key == "heartRateComponent" ? "Heart Rate:" :
                                                 key == "sleepComponent" ? "Sleep:" :
                                                 key.capitalized)
                                                .foregroundColor(Color(red:0.894, green: 0.949, blue: 0.839))
                                            Spacer()
                                            Text(String(format: "%.0f", value))
                                                .foregroundColor(Color(red:0.894, green: 0.949, blue: 0.839))
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(10)
                            .padding()
                        }                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Image("Icon")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 30)
                    }
                    
                    ToolbarItem(placement: .principal) {
                        HStack {
                            Text(monthYearString(from: currentMonth))
                                .foregroundColor(Color(red:0.894, green: 0.949, blue: 0.839))
                            
                            Button(action: previousMonth) {
                                Image(systemName: "chevron.left")
                                    .foregroundColor(Color(red:0.894, green: 0.949, blue: 0.839))
                            }
                            
                            Button(action: nextMonth) {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(Color(red:0.894, green: 0.949, blue: 0.839))
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(Color(red:0.894, green: 0.949, blue: 0.839))
                        }
                    }
                }
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
        dailyValues.removeAll()
        
        await calculateNormalization()
        
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: currentMonth)!
        var date = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let today = calendar.startOfDay(for: Date())
        
        while date >= interval.start {
            if date < today {
                do {
                    let score = try await firestoreManager.getComputedData(userId: authManager.user?.uid ?? "", metric: .bandwidth, date: date)
                    dailyValues[date] = score
                } catch {
                    print("Error getting Bandwidth score for \(date): \(error)")
                }
            }
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
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
                if let score = try? await firestoreManager.getComputedData(
                    userId: authManager.user?.uid ?? "",
                    metric: .bandwidth,
                    date: date
                ) {
                    allValues.append(score)
                }
            }
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        if !allValues.isEmpty {
            let min = allValues.min() ?? 0
            let max = allValues.max() ?? 100
            
            normalization = MetricNormalization(
                min: min,
                max: max,
                shouldInvert: false
            )
        }
    }
    
    private func loadComponents(for date: Date) async {
        components.removeAll()
        
        let metrics: [ComputedMetric] = [
            .heartRateComponent,
            .exerciseComponent,
            .sleepComponent
        ]
        
        for metric in metrics {
            if let value = try? await firestoreManager.getComputedData(
                userId: authManager.user?.uid ?? "",
                metric: metric,
                date: date
            ) {
                components[metric.rawValue] = value
            }
        }
    }}


struct DayCell: View {
    let date: Date
    let value: Double
    let normalization: MetricNormalization?
    let onTap: () -> Void
    let isSelected: Bool
    
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
                    if value != 0 {
                        Text(formatValue())
                            .font(.custom("KulimPark-SemiBold", size: 8))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            isSelected ?
                Circle()
                    .stroke(style: StrokeStyle(
                        lineWidth: 2,
                        dash: [5]
                    ))
                    .foregroundColor(Color(red:0.894, green: 0.949, blue: 0.839))
                : nil
        )
                .onTapGesture {
                    onTap()
                }
    }
    
    private func formatValue() -> String {
            return String(format: "%.0f", value)
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
