import SwiftUI

struct CastLibraryView: View {
  @EnvironmentObject private var app: AppState
  @State private var name = ""
  @State private var bible = ""

  var body: some View {
    NavigationStack {
      List {
        Section("New member") {
          TextField("Name", text: $name)
          TextField("Bible (optional)", text: $bible, axis: .vertical)
            .lineLimit(2 ... 6)
          Button("Create") {
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty else { return }
            Task {
              await app.createCastMember(
                name: n,
                bible: bible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : bible
              )
              name = ""
              bible = ""
            }
          }
        }
        Section("Cast") {
          ForEach(app.cast) { m in
            VStack(alignment: .leading, spacing: 4) {
              Text(m.name).font(.headline)
              Text(m.id).font(.caption2).foregroundStyle(.secondary)
              if let b = m.bible, !b.isEmpty {
                Text(b).font(.caption).lineLimit(3)
              }
              if let lora = m.lora_status {
                Text("LoRA: \(lora)").font(.caption2)
              }
            }
          }
        }
      }
      .navigationTitle("Cast")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await app.refreshCast() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
        }
      }
      .task { await app.refreshCast() }
    }
  }
}
