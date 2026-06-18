//
//  DocumentPreview.swift
//  Óculo
//
//  Popup de preview en hover (calmo, con retardo): metadata + acciones a la
//  izquierda, primera página a la derecha. Usa .popover (interactivo y fiable):
//  se mantiene mientras el ratón está sobre la tarjeta o sobre el panel.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Contenido del popup: metadata + acciones (izquierda), primera página (derecha).
struct DocumentPreviewPanel: View {
    let entry: LibraryEntry
    let libraryRoot: URL
    let libraryName: String
    let vaultStore: VaultStore
    let recents: RecentsStore
    let requestAddToTag: ([DocRef]) -> Void   // abre el selector de tag (vive en la ventana principal)
    let onQuickLook: () -> Void
    let onClose: () -> Void

    @State private var thumbnail: NSImage?
    @State private var vaultNote: VaultNote?
    @State private var fields: [MetadataField] = []
    @State private var fileSize: String?
    @State private var typeDescription: String?
    @State private var pageCount: Int?

    private let pageSize = CGSize(width: 176, height: 232)

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            info
                .frame(width: 196, alignment: .leading)

            VStack(spacing: 6) {
                firstPage
                    .frame(width: pageSize.width, height: pageSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.black.opacity(0.12))
                    )
                if let pageCount {
                    Text(T("Page 1 of \(pageCount)", "Página 1 de \(pageCount)"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .task(id: entry.id) { await load() }
    }

    // MARK: Izquierda — metadata + acciones

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.docType?.label ?? "DOC")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.docType?.accentColor ?? .gray)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill((entry.docType?.accentColor ?? .gray).opacity(0.18)))

            Text(entry.name)
                .font(.headline)
                .lineLimit(3)
                .padding(.top, 11)

            VStack(alignment: .leading, spacing: 3) {
                if let path = relativeCategory { secondary(path) }
                if let typeDescription { secondary(typeDescription) }
                if let fileSize { secondary(fileSize) }
                if let date = entry.modified {
                    secondary(T("Edited ", "Editado ") + date.formatted(.relative(presentation: .named).locale(Localization.shared.locale)))
                }
            }
            .padding(.top, 7)

            if let vaultNote {
                Divider().padding(.vertical, 9)
                vaultMetadata(vaultNote)
            } else if !fields.isEmpty {
                Divider().padding(.vertical, 9)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(fields) { field in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(field.key.capitalized)
                                .foregroundStyle(.secondary)
                                .frame(width: 62, alignment: .leading)
                            Text(field.value)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                    }
                }
            }

            Spacer(minLength: 12)
            Divider().padding(.bottom, 7)

            action(T("Open", "Abrir"), icon: "arrow.up.forward.app", key: "Return") {
                recents.record(url: entry.resolvedURL, library: libraryName, noteID: vaultNote?.id)
                DocumentActions.openInNativeApp(entry.resolvedURL); onClose()
            }
            action(T("Show in Finder", "Mostrar en Finder"), icon: "folder", key: "F") {
                DocumentActions.revealInFinder(entry.resolvedURL); onClose()
            }
            action("Quick Look", icon: "eye", key: "Space") {
                onQuickLook()
            }
            action(T("Add tag", "Añadir tag"), icon: "tag", key: "T") {
                requestAddToTag([docRef])
            }
        }
    }

    /// Referencia portable de este documento, clavada a id de nota si está digerido.
    private var docRef: DocRef {
        DocRef(url: entry.resolvedURL, library: libraryName, noteID: vaultNote?.id)
    }

    /// Metadata proveniente de la nota de bóveda emparejada por content_hash.
    @ViewBuilder
    private func vaultMetadata(_ note: VaultNote) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(T("In vault", "En bóveda"), systemImage: "checkmark.seal")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !note.tags.isEmpty { metaRow(T("Tags", "Tags"), note.tags.joined(separator: ", ")) }
        }
    }

    private func metaRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(key).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
            Text(value).foregroundStyle(.primary).lineLimit(3)
        }
        .font(.caption)
    }

    private func secondary(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func action(_ label: String, icon: String, key: String?, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 9) {
                Image(systemName: icon).frame(width: 16)
                Text(label)
                Spacer(minLength: 8)
                if let key {
                    Text(key)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                }
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }

    // MARK: Derecha — primera página

    @ViewBuilder
    private var firstPage: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)  // apaisados enteros, sin recorte
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .overlay(ProgressView().controlSize(.small))
        }
    }

    // MARK: Carga

    private var relativeCategory: String? {
        relativeCategoryPath(of: entry.displayURL, root: libraryRoot)
    }

    private func load() async {
        let resolved = entry.resolvedURL
        async let loadedSize = Task.detached { fileSizeString(for: resolved) }.value
        async let loadedType = Task.detached { typeDescriptionString(for: resolved) }.value
        async let loadedPages = Task.detached { pdfPageCount(for: resolved) }.value

        // Metadata canónica: nota de bóveda (por content_hash); sidecar como reserva.
        let note = await vaultStore.note(forDocumentAt: resolved)
        vaultNote = note
        if note == nil {
            fields = await Task.detached { SidecarLoader.load(for: resolved) }.value
        }

        thumbnail = await ThumbnailLoader.firstPage(of: resolved, size: pageSize, scale: 2)
        fileSize = await loadedSize
        typeDescription = await loadedType
        pageCount = await loadedPages
    }
}

// MARK: - Apoyos (nonisolated, fuera de la vista)

private nonisolated func fileSizeString(for url: URL) -> String? {
    guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
    return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
}

private nonisolated func typeDescriptionString(for url: URL) -> String? {
    (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.localizedDescription
}

private nonisolated func pdfPageCount(for url: URL) -> Int? {
    guard url.pathExtension.lowercased() == "pdf",
          let document = PDFDocument(url: url) else { return nil }
    return document.pageCount
}

/// Ruta de categoría relativa a la raíz de la biblioteca (p. ej. "AI & Tech / Papers").
private nonisolated func relativeCategoryPath(of displayURL: URL, root: URL) -> String? {
    let rootComponents = root.standardizedFileURL.pathComponents
    let parentComponents = displayURL.standardizedFileURL.deletingLastPathComponent().pathComponents
    guard parentComponents.count >= rootComponents.count else { return nil }
    let tail = parentComponents.dropFirst(rootComponents.count)
    return tail.isEmpty ? nil : tail.joined(separator: " / ")
}
