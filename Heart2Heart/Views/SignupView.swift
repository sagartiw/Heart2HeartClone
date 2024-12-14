
// SignUpView.swift
import SwiftUI

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    
    private let buttonWidth: CGFloat = 200
    private let buttonHeight: CGFloat = 44
    
    var body: some View {
        NavigationView {
            ZStack {
                
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.10, green: 0.08, blue: 0.14),
                        Color(red: 0.22, green: 0.16, blue: 0.31)
                    ]), startPoint: .init(x: 0, y: 0), endPoint: .init(x: 1, y: 1)
                ).ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image("Logo")
                    .resizable() // Make the image resizable
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                
                Text("Create Account")
                    .font(.custom("KulimPark-SemiBold", size: 24))
                
                TextField("Name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Sign Up") {
                    Task {
                        do {
                            try await authManager.signUp(email: email, password: password, name: name)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .frame(width: buttonWidth, height: buttonHeight)
                .background(Color(red:0.894,green: 0.949, blue: 0.839))
                .foregroundColor(.black)
                .cornerRadius(8)
                
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                }
            }
        }
    }
}
