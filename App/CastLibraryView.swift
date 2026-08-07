import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VivijureKit

struct CastLibraryView: View {
  @EnvironmentObject private var app: AppState
  @State private var name = ""
  @State private var bible = ""
  @State private var showImport = false

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
          Button("Import .vvcast…") {
            showImport = true
          }
        }
        Section("Cast") {
          ForEach(app.cast) { m in
            NavigationLink {
              CastDetailView(memberId: m.id)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(m.name).font(.headline)
                Text(m.id).font(.caption2).foregroundStyle(.secondary)
                if let b = m.bible, !b.isEmpty {
                  Text(b).font(.caption).lineLimit(2)
                }
                HStack(spacing: 8) {
                  if m.portrait_key != nil {
                    Label("portrait", systemImage: "person.crop.square")
                  }
                  Text("\(m.refKeys.count) refs")
                  if let lora = m.lora_status {
                    Text("LoRA: \(lora)")
                  }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
              }
            }
            .swipeActions {
              Button(role: .destructive) {
                Task { await app.deleteCastMember(id: m.id) }
              } label: {
                Label("Delete", systemImage: "trash")
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
      .fileImporter(
        isPresented: $showImport,
        allowedContentTypes: [.data, .archive, UTType(filenameExtension: "vvcast") ?? .data],
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls):
          guard let url = urls.first else { return }
          Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
              let data = try Data(contentsOf: url)
              await app.importCastTar(data)
            } catch {
              app.lastError = error.localizedDescription
            }
          }
        case .failure(let err):
          app.lastError = err.localizedDescription
        }
      }
    }
  }
}

struct CastDetailView: View {
  @EnvironmentObject private var app: AppState
  let memberId: String

  @State private var editName = ""
  @State private var editBible = ""
  @State private var photoItem: PhotosPickerItem?
  @State private var uploadKind: VivijureClient.CastMediaKind = .portrait
  @State private var loraDetail = ""
  @State private var exportURL: URL?
  @State private var showExportShare = false

  private var member: CastMember? {
    app.cast.first { $0.id == memberId }
  }

  var body: some View {
    Form {
      if let m = member {
        Section("Identity") {
          TextField("Name", text: $editName)
          TextField("Bible", text: $editBible, axis: .vertical)
            .lineLimit(3 ... 8)
          Button("Save") {
            Task {
              await app.patchCastMember(
                id: m.id,
                name: editName,
                bible: editBible,
                voiceId: m.voice_id
              )
            }
          }
          if let voice = m.voice_id {
            LabeledContent("voice_id", value: voice)
          }
          LabeledContent("id", value: m.id)
        }

        Section("Media") {
          if let pk = m.portrait_key {
            Text("Portrait: \(pk)")
              .font(.caption2.monospaced())
              .lineLimit(2)
          } else {
            Text("No portrait").foregroundStyle(.secondary)
          }
          Text("Refs: \(m.refKeys.count) · Sources: \(m.sourceKeys.count)")
            .font(.caption)

          Picker("Upload as", selection: $uploadKind) {
            Text("Portrait").tag(VivijureClient.CastMediaKind.portrait)
            Text("Training ref").tag(VivijureClient.CastMediaKind.ref)
            Text("Source photo").tag(VivijureClient.CastMediaKind.source)
          }
          PhotosPicker(selection: $photoItem, matching: .images) {
            Label("Pick photo from library", systemImage: "photo")
          }
          .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await uploadPicked(item, memberId: m.id) }
          }

          if !m.refKeys.isEmpty {
            ForEach(m.refKeys, id: \.self) { key in
              Text(key).font(.caption2.monospaced()).lineLimit(1)
            }
          }
        }

        Section("Generate refs (cast.image)") {
          Button("Generate refs from portrait/sources") {
            Task { await app.generateCastRefs(id: m.id) }
          }
          .disabled(app.busy || m.portrait_key == nil)
        }

        Section("Training") {
          if let st = m.lora_status {
            Text("Status: \(st)")
          }
          Button("Train SDXL LoRA") {
            Task { await app.trainCastLora(id: m.id, wan: false) }
          }
          .disabled(app.busy || m.portrait_key == nil)
          Button("Train Wan LoRA") {
            Task { await app.trainCastLora(id: m.id, wan: true) }
          }
          .disabled(app.busy || m.portrait_key == nil)
          Button("Refresh LoRA status") {
            Task { await pollLora(m.id) }
          }
          if !loraDetail.isEmpty {
            Text(loraDetail).font(.caption2.monospaced())
          }
        }

        Section("Portable bundle") {
          Button("Export .vvcast") {
            Task { await exportVV(m) }
          }
          .disabled(app.busy)
        }

        Section {
          Button("Delete member", role: .destructive) {
            Task { await app.deleteCastMember(id: m.id) }
          }
        }
      } else {
        Text("Member not in catalog (refresh cast list).")
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle(member?.name ?? "Cast")
    .onAppear {
      if let m = member {
        editName = m.name
        editBible = m.bible ?? ""
      }
    }
    .onChange(of: member?.name) { _ in
      if let m = member {
        editName = m.name
        editBible = m.bible ?? ""
      }
    }
    .sheet(isPresented: $showExportShare) {
      if let exportURL {
        ShareSheet(items: [exportURL])
      }
    }
  }

  private func exportVV(_ m: CastMember) async {
    guard let data = await app.exportCastData(id: m.id) else { return }
    let name = m.name
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: " ", with: "-")
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(name).vvcast")
    do {
      try data.write(to: url, options: .atomic)
      exportURL = url
      showExportShare = true
    } catch {
      app.lastError = error.localizedDescription
    }
  }

  private func uploadPicked(_ item: PhotosPickerItem, memberId: String) async {
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        app.lastError = "Could not load image data"
        return
      }
      let mime = ImageMime.sniff(data) ?? "image/jpeg"
      await app.uploadCastImage(id: memberId, kind: uploadKind, data: data, mime: mime)
      photoItem = nil
    } catch {
      app.lastError = error.localizedDescription
    }
  }

  private func pollLora(_ id: String) async {
    guard let client = app.client else { return }
    do {
      let r = try await client.loraStatus(castId: id)
      if let view = r.view {
        loraDetail = view.prettyJSON()
      } else {
        loraDetail = r.status ?? "no training view"
      }
      await app.refreshCast()
    } catch {
      app.lastError = error.localizedDescription
    }
  }
}

/// Minimal UIActivityViewController wrapper for exporting .vvcast.
struct ShareSheet: UIViewControllerRepresentable {
  var items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
