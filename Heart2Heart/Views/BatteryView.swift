import SwiftUI

struct BatteryView: View {
    let value: Double
    let minValue: Double
    let maxValue: Double
    let isInverted: Bool
    let averageValue: Double?  // Make this optional
    let isEmpty: Bool
    
    private var batteryImageName: String {
        let score = Int(value)
        
        switch score {
        case ...0:
            return "EmptyBattery"
        case 1...20:
            return "BatteryLevel1"
        case 21...40:
            return "BatteryLevel2"
        case 41...60:
            return "BatteryLevel3"
        case 61...80:
            return "BatteryLevel4"
        case 81...100:
            return "BatteryLevel5"
        default:
            return "EmptyBattery"
        }
        
    }
    
    var body: some View {
        GeometryReader { geometry in
            Image(batteryImageName)
                .resizable()
                .scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
    
    /*private let fillRatio: CGFloat = 0.68
    private let widthToHeightRatio: CGFloat = 0.343
    
    private var normalizedValue: CGFloat {
        let range = maxValue - minValue
        let value = isInverted ? (maxValue - value) : (value - minValue)
        return CGFloat(min(1, max(0, value / range)))
    }
    
    private var normalizedAverageValue: CGFloat? {
        guard let averageValue = averageValue else { return nil }
        let range = maxValue - minValue
        let value = isInverted ? (maxValue - averageValue) : (averageValue - minValue)
        return CGFloat(min(1, max(0, value / range)))
    }
    
    private var fillColor: Color {
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
                Image("Battery")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                
                if !isEmpty {
                    BatteryFill(
                        height: normalizedValue * geometry.size.height * fillRatio,
                        width: batteryWidth,
                        fillColor: fillColor
                    )
                    .foregroundColor(fillColor)
                    .padding(.bottom, geometry.size.height * 0.05)
                    
                    // Only show average line if averageValue exists
                    if let normalizedAverage = normalizedAverageValue {
                        CurvedDottedLine(
                            width: batteryWidth * 0.85,
                            height: normalizedAverage * geometry.size.height * fillRatio,
                            text: "average"
                        )
                        .padding(.bottom, geometry.size.height * 0.06)
                    }
                }
            }
        }
        .aspectRatio(widthToHeightRatio, contentMode: .fit)
    }
}

// Preview now becomes simpler:
//struct BatteryView_Previews: PreviewProvider {
//    static var previews: some View {
//        VStack(spacing: 20) {
//            BatteryView(
//                value: 100,
//                minValue: 0,
//                maxValue: 100,
//                isInverted: false,
//                averageValue: 90
//            )
//            .frame(height: 140)
            
//            BatteryView(
//                value: 60,
//                minValue: 0,
//                maxValue: 100,
//                isInverted: false,
//                averageValue: 60
//            )
//            .frame(height: 70)
//            
//            BatteryView(
//                value: 25,
//                minValue: 0,
//                maxValue: 100,
//                isInverted: false,
//                averageValue: 50
//            )
//            .frame(height: 35)
//        }
//        .padding()
//    }
//}

struct CurvedDottedLine: View {
    let width: CGFloat
    let height: CGFloat
    let text: String
    
    var body: some View {
        let curveHeight = width * 0.12
        
        ZStack {
            // Dotted line
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(
                    to: CGPoint(x: width, y: 0),
                    control: CGPoint(x: width/2, y: curveHeight)
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 2])) // Smaller dashes
            
            // Text below line
            Text(text)
                .offset(y: curveHeight * 0.6) // Always below the line
        }
        .frame(width: width, height: width * 0.03)
        .font(.custom("KulimPark-SemiBold", size: 12))
        .foregroundColor(Color(red:0.894,green: 0.949, blue: 0.839))
        .offset(y: -height)
    }
}


private struct BatteryFill: View {
    let height: CGFloat
    let width: CGFloat
    let fillColor: Color
    
    private let ellipseHeightRatio: CGFloat = 0.17
    private let widthScaleFactor: CGFloat = 0.915
    
    private var darkerFillColor: Color {
        if let components = UIColor(fillColor).cgColor.components {
            return Color(
                red: components[0] * 0.8,
                green: components[1] * 0.8,
                blue: components[2] * 0.8
            )
        }
        return fillColor
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main rectangle with fill
            Rectangle()
                .frame(width: width * widthScaleFactor, height: height)
                .foregroundColor(fillColor)
                .overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.2),
                            Color.black.opacity(0)
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            
            let ellipseHeight = width * ellipseHeightRatio
            
            // Top half ellipse (background color)
            Ellipse()
                .foregroundColor(Color(red: 0.141, green: 0.141, blue: 0.141)) // Or whatever your app's background color is
                .frame(width: width * widthScaleFactor, height: ellipseHeight)
                .clipShape(Rectangle().offset(y: ellipseHeight/2))
                .offset(y: -height + ellipseHeight/2)
            
            // Bottom half ellipse (darker)
            Ellipse()
                .foregroundColor(darkerFillColor)
                .frame(width: width * widthScaleFactor, height: ellipseHeight)
                .clipShape(Rectangle().offset(y: ellipseHeight/2))
                .offset(y: ellipseHeight/2)
        }
    }
}*/
