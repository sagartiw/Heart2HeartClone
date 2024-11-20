//Views/InvitationCodeView

import SwiftUI

struct InvitationCodeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Binding var isPresented: Bool
    
    @State private var code: [String] = Array(repeating: "", count: 6)
    @FocusState private var focusedField: Int?
    @State private var showAlert = false
    @State private var alertType: AlertType = .error("")
    @State private var partnerName = ""
    @State private var partnerUserId = ""
    @State private var isLoading = false
    
    private enum AlertType {
        case error(String)
        case confirmation(String)
        
        var title: String {
            switch self {
            case .error: return "Error"
            case .confirmation: return "Confirm Pairing"
            }
        }
        
        var message: String {
            switch self {
            case .error(let message): return message
            case .confirmation(let name): return "Pair with \(name)?"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Enter Invitation Code")
                .font(.title)
            
            codeFieldsView
            
            Button("Submit", action: validateAndPair)
                .buttonStyle(.borderedProminent)
            
            Button("Cancel") {
                isPresented = false
            }
            .foregroundColor(.gray)
        }
        .padding()
        .alert(alertType.title, isPresented: $showAlert) {
            if case .confirmation(_) = alertType {
                Button("Cancel", role: .cancel) { }
                Button("Pair", action: completePairing)
            } else {
                Button("OK", role: .cancel) { }
            }
        } message: {
            Text(alertType.message)
        }
        .onAppear {
            focusedField = 0
        }
        .disabled(isLoading)
        .overlay {
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
            }
        }
    }
    
    private var codeFieldsView: some View {
        HStack(spacing: 20) {
            ForEach(0..<2) { group in
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        let arrayIndex = group * 3 + index
                        codeTextField(index: arrayIndex)
                    }
                }
            }
        }
    }
    
    private func codeTextField(index: Int) -> some View {
        TextField("", text: $code[index])
            .frame(width: 50, height: 60)
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 2))
            .focused($focusedField, equals: index)
            .onChange(of: code[index]) { newValue in
                handleCodeInput(index: index, newValue: newValue)
            }
    }
    
    private func handleCodeInput(index: Int, newValue: String) {
        if newValue.count > 1 {
            code[index] = String(newValue.prefix(1))
        }
        if newValue.count == 1 && index < 5 {
            focusedField = index + 1
        }
    }
    
    private func validateAndPair() {
        isLoading = true
        Task {
            do {
                let enteredCode = code.joined()
                let partner = try await authManager.validateAndGetPartner(code: enteredCode)
                await MainActor.run {
                    partnerName = partner.name
                    partnerUserId = partner.id
                    alertType = .confirmation(partnerName)
                    showAlert = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    alertType = .error(error.localizedDescription)
                    showAlert = true
                    isLoading = false
                }
            }
        }
    }
    
    private func completePairing() {
        isLoading = true
        Task {
            do {
                try await authManager.completePairing(withPartnerId: partnerUserId)
                await MainActor.run {
                    isLoading = false
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    alertType = .error(error.localizedDescription)
                    showAlert = true
                    isLoading = false
                }
            }
        }
    }
}
