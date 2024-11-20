//Views/SmallBatteryView

import SwiftUI

struct SmallBatteryView: View {
    let value: Double
    let minValue: Double
    let maxValue: Double
    let isInverted: Bool
    let isEmpty: Bool
    let isGray: Bool
    
    private let fillRatio: CGFloat = 0.77  // Increased from 0.57
    private let widthToHeightRatio: CGFloat = 0.45
    private let fillOffsetRatio: CGFloat = 0.08
    
    private var normalizedValue: CGFloat {
        let range = maxValue - minValue
        let value = isInverted ? (maxValue - value) : (value - minValue)
        return CGFloat(min(1, max(0, value / range)))
    }
    
    private var fillColor: Color {
        if isGray {
            return Color(.gray)
        }
        let percentage = normalizedValue
        return Color(
            red: 1 - percentage,
            green: percentage,
            blue: 0
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            let batteryWidth = geometry.size.height * widthToHeightRatio
            
            ZStack(alignment: .bottom) {
                if !isEmpty {
                    SmallBatteryFill(
                        height: normalizedValue * geometry.size.height * fillRatio,
                        width: batteryWidth,
                        fillColor: fillColor
                    )
                    .foregroundColor(fillColor)
                    .offset(y: -geometry.size.height * fillOffsetRatio)
                }
                
                Image("SmallBattery")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            }
        }
        .aspectRatio(widthToHeightRatio, contentMode: .fit)
    }
}


private struct SmallBatteryFill: View {
    let height: CGFloat
    let width: CGFloat
    let fillColor: Color
    
    private let ellipseHeightRatio: CGFloat = 0.17
    private let widthScaleFactor: CGFloat = 0.9
    
    private var darkerFillColor: Color {
        if let components = UIColor(fillColor).cgColor.components {
            return Color(
                red: components[0] * 0.6,
                green: components[1] * 0.6,
                blue: components[2] * 0.6
            )
        }
        return fillColor
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .frame(width: width * widthScaleFactor, height: height)
                .foregroundColor(fillColor)
                .overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.4),
                            Color.black.opacity(0)
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            
            let ellipseHeight = width * ellipseHeightRatio
            
            // Bottom half ellipse (darker)
            Ellipse()
                .foregroundColor(darkerFillColor)
                .frame(width: width * widthScaleFactor, height: ellipseHeight)
                .clipShape(Rectangle().offset(y: ellipseHeight/2))
                .offset(y: ellipseHeight/2)
        }
    }
}

// Add this at the bottom of your file
#Preview("Battery States") {
    VStack(spacing: 20) {
        // Full Battery
        SmallBatteryView(
            value: 100,
            minValue: 0,
            maxValue: 100,
            isInverted: false,
            isEmpty: false,
            isGray: false
        )
        .frame(height: 100)
        
    
    }
}
