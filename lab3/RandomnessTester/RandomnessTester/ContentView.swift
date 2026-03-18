//
//  ContentView.swift
//  StreamCipherApp
//
//  Лабораторная работа №1
//
//

import SwiftUI
import CryptoKit

// SHA-1
func sha1Hex(_ data: Data) -> String {
    Insecure.SHA1.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

func passwordSeed(_ password: String) -> UInt64 {
    let digest = Insecure.SHA1.hash(data: Data(password.utf8))
    var seed: UInt64 = 0
    for (i, byte) in digest.prefix(8).enumerated() {
        seed |= UInt64(byte) << (56 - i * 8)
    }
    return seed
}

//LCG
struct LCGGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextByte() -> UInt8 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return UInt8((state >> 33) & 0xFF)
    }

    mutating func nextBit() -> UInt8 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return UInt8((state >> 33) & 1)
    }
}

//XOR
func xorStreamChunk(_ chunk: ArraySlice<UInt8>, prng: inout LCGGenerator) -> [UInt8] {
    chunk.map { $0 ^ prng.nextByte() }
}

@MainActor
final class CipherViewModel: ObservableObject {

    @Published var password: String = ""
    @Published var sha1Text: String = "—"
    @Published var statusText: String = "Готово к работе"
    @Published var progressValue: Double = 0.0
    @Published var isWorking: Bool = false
    @Published var logText: String = ""
    @Published var inputFileName: String = "Файл не выбран"
    @Published var outputFileName: String = "Файл не выбран"

    private(set) var inputURL: URL? = nil


    func computeHash() {
        guard !password.isEmpty else {
            sha1Text = "—"
            appendLog("Пароль пуст")
            return
        }
        sha1Text = sha1Hex(Data(password.utf8))
        let seed = passwordSeed(password)
        appendLog(" Пароль: «\(password)»")
        appendLog("   SHA-1  → \(sha1Text)")
        appendLog("   ГПСЧ (первые 8 байт SHA-1): 0x\(String(format: "%016X", seed))")
    }

    func setInputURL(_ url: URL) {
        inputURL = url
        inputFileName = url.lastPathComponent
        appendLog("Входной файл: \(url.lastPathComponent)")
    }

    func processFile(outputURL: URL, operationName: String) async {
        guard !password.isEmpty else {
            appendLog("Введите пароль")
            return
        }
        guard let inputURL else {
            appendLog("Входной файл не выбран")
            return
        }

        outputFileName = outputURL.lastPathComponent
        isWorking = true
        progressValue = 0.0
        statusText = "\(operationName)…"

        appendLog("\(operationName) начато")
        appendLog("  Вход:  \(inputURL.lastPathComponent)")
        appendLog("  Выход: \(outputURL.lastPathComponent)")

        do {
            let inputData = try Data(contentsOf: inputURL)
            let totalBytes = inputData.count
            appendLog("  Размер: \(totalBytes) байт (\(String(format: "%.2f", Double(totalBytes)/1024)) КБ)")

            let seed = passwordSeed(password)
            var prng = LCGGenerator(seed: seed)

            let chunkSize = 65_536
            let inputBytes = [UInt8](inputData)
            var outputBytes = [UInt8]()
            outputBytes.reserveCapacity(totalBytes)

            var processed = 0
            while processed < totalBytes {
                let end = min(processed + chunkSize, totalBytes)
                outputBytes.append(contentsOf: xorStreamChunk(inputBytes[processed..<end], prng: &prng))
                processed = end
                progressValue = Double(processed) / Double(totalBytes)
                await Task.yield()
            }

            try Data(outputBytes).write(to: outputURL)

            progressValue = 1.0
            statusText = "\(operationName) завершено ✓"
            appendLog("Готово → \(outputURL.lastPathComponent)")

        } catch {
            statusText = "Ошибка ✗"
            appendLog(" \(error.localizedDescription)")
        }

        isWorking = false
    }

    func appendLog(_ msg: String) {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        logText += "[\(df.string(from: Date()))]  \(msg)\n"
    }

    func clearLog() { logText = "" }
}

struct ContentView: View {

    @StateObject private var vm = CipherViewModel()
    @State private var mode: CipherMode = .encrypt

    enum CipherMode: String, CaseIterable {
        case encrypt = "Шифрование"
        case decrypt = "Дешифрование"
        var icon: String { self == .encrypt ? "lock.fill" : "lock.open.fill" }
        var tint: Color  { self == .encrypt ? .blue : .orange }
    }

    var body: some View {
        NavigationStack {
            HSplitView {
                leftPanel.frame(minWidth: 380, maxWidth: 480)
                rightPanel.frame(minWidth: 320)
            }
            .navigationTitle("Потоковый шифр · Вариант 6 · SHA-1")
        }
        .frame(minWidth: 820, minHeight: 540)
    }

    private var leftPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                GroupBox(label: Label("Пароль", systemImage: "key.fill")) {
                    VStack(alignment: .leading, spacing: 10) {

                        HStack {
                            SecureField("Введите пароль…", text: $vm.password)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { vm.computeHash() }
                            Button("SHA-1") { vm.computeHash() }
                                .buttonStyle(.borderedProminent)
                                .disabled(vm.password.isEmpty)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("SHA-1 хеш пароля:")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(vm.sha1Text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(vm.sha1Text == "—" ? .secondary : .primary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(8)
                }

                GroupBox(label: Label("Операция", systemImage: "doc.fill")) {
                    VStack(alignment: .leading, spacing: 12) {

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Входной файл:")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(vm.inputFileName)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(vm.inputFileName.contains("не выбран") ? .secondary : .primary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button("Выбрать…") { pickInput() }
                                .controlSize(.small)
                        }

                        Divider()

                        if vm.outputFileName != "Файл не выбран" {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Файл результата:")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(vm.outputFileName)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                            Divider()
                        }

                        // Выбор режима
                        Picker("", selection: $mode) {
                            ForEach(CipherMode.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        // Кнопка запуска
                        Button {
                            pickOutputAndRun()
                        } label: {
                            Label(mode.rawValue + " и сохранить…", systemImage: mode.icon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(mode.tint)
                        .controlSize(.large)
                        .disabled(vm.isWorking || vm.password.isEmpty || vm.inputURL == nil)
                    }
                    .padding(8)
                }

                GroupBox(label: Label("Состояние", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        if vm.isWorking {
                            ProgressView(value: vm.progressValue).progressViewStyle(.linear)
                            Text("\(Int(vm.progressValue * 100))%  —  \(vm.statusText)")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(vm.statusText)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                Spacer()
            }
            .padding()
        }
    }

    private var rightPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Журнал", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                    .padding(12)
                Spacer()
                Button("Очистить") { vm.clearLog() }
                    .font(.caption)
                    .padding(.trailing, 12)
            }
            .background(Color(NSColor.windowBackgroundColor))
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    Text(vm.logText.isEmpty ? "Журнал пуст…" : vm.logText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("bottom")
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: vm.logText) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }

    private func pickInput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            vm.setInputURL(url)
        }
    }

    private func pickOutputAndRun() {
        guard let inputURL = vm.inputURL else { return }
        let panel = NSSavePanel()
        let suffix = mode == .encrypt ? "_enc" : "_dec"
        let base = inputURL.deletingPathExtension().lastPathComponent
        let ext  = inputURL.pathExtension.isEmpty ? "bin" : inputURL.pathExtension
        panel.nameFieldStringValue = "\(base)\(suffix).\(ext)"
        if panel.runModal() == .OK, let outURL = panel.url {
            Task { await vm.processFile(outputURL: outURL, operationName: mode.rawValue) }
        }
    }
}

#Preview { ContentView() }
