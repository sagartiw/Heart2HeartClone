//
//  GradientBackgroundModifier.swift
//  Heart2Heart
//
//  Created by Aristides Peralta on 11/29/24.
//

import SwiftUI

struct DiagonalGradientBackground: ViewModifier {
    
    /*func setGradientBackgroud(content: Content) -> some View {
        let colorTop = Color(red: 0.10, green: 0.08, blue: 0.14)
        let colorBottom = Color(red: 0.22, green: 0.16, blue: 0.31)
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [colorTop, colorBottom]
        gradientLayer.locations = [0.0, 1.0]
        gradientLayer.frame = self.view.bounds
        
        content.view.layer.insertSublayer(gradientLayer, at: 0)
    }*/
    
    func body(content: Content) -> some View {
        ZStack{
            content.background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.10, green: 0.08, blue: 0.14),
                        Color(red: 0.22, green: 0.16, blue: 0.31)
                    ]), startPoint: .init(x: 0, y: 0), endPoint: .init(x: 1, y: 1)
                ).ignoresSafeArea(edges: .all)
            )
            
            content
        }
    }
}

extension View {
    func diagonalGradientBackground() -> some View {
        self.modifier(DiagonalGradientBackground())
    }
}
