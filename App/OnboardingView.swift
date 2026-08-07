import SwiftUI

struct OnboardingView: View {
  @EnvironmentObject private var app: AppState
  @State private var url: String = ""
  @State private var token: String = ""
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Connect to a Vivijure Studio host (same API as the web planner).")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Section("Studio") {
          TextField("https://studio.example.com", text: $url)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
          SecureField("API token (Bearer)", text: $token)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        if let error {
          Section {
            Text(error).foregroundStyle(.red)
          }
        }
        Section {
          Button("Connect") {
            connect()
          }
          .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        Section("Help") {
          Text("Mint a token on the studio (operator or named consumer). Hosted tenants use the token from control plane.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Vivijure")
      .onAppear {
        url = app.studioURLString
        token = app.token
      }
    }
  }

  private func connect() {
    error = nil
    let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parsed = URL(string: u), parsed.scheme == "https" || parsed.scheme == "http" else {
      error = "Enter a full URL including https://"
      return
    }
    app.saveCredentials(url: u, token: token)
  }
}
