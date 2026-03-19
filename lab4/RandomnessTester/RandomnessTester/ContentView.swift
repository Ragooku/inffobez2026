//
//  ContentView.swift
//  BlockCipherApp
//
//  Лабораторная работа №1
//
//

import SwiftUI
import CryptoKit


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

    init(seed: UInt64) { state = seed }

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

//GOST
struct GOST28147 {
    static let sBox: [[UInt8]] = [
        [9,  6,  3,  2,  8, 11,  1,  7, 10,  4, 14, 15, 12,  0, 13,  5],
        [3,  7, 14,  9,  8, 10,  2,  5,  6,  0, 11, 15, 13,  1,  4, 12],
        [14,  4,  6,  2, 11,  3, 13,  8, 12, 15,  5, 10,  0,  7,  1,  9],
        [14,  7, 10, 12, 13,  1,  3,  9,  0,  2, 11,  4, 15,  8,  5,  6],
        [11,  5,  1,  9,  8, 13, 15,  0, 14,  4,  2,  3, 12,  7, 10,  6],
        [ 3, 10, 13, 12,  1,  2,  0, 11,  7,  5,  9,  4,  8, 15, 14,  6],
        [ 1, 13,  2,  9,  7, 10,  6,  0,  8, 12,  4,  5, 15,  3, 11, 14],
        [11, 10, 15,  5,  0, 12, 14,  8,  6,  2,  3,  9,  1,  7, 13,  4]
    ]

    static let delta1: UInt32 = 0x01010101
    static let delta2: UInt32 = 0x01010104

    
    static func keySchedule(from keyBytes: [UInt8]) -> [UInt32] {
        precondition(keyBytes.count == 32, "ключ должен быть 32 байта")
        return (0..<8).map { i in
            let b = i * 4
            return UInt32(keyBytes[b])
                 | UInt32(keyBytes[b + 1]) << 8
                 | UInt32(keyBytes[b + 2]) << 16
                 | UInt32(keyBytes[b + 3]) << 24
        }
    }

    static func roundFunction(_ x: UInt32, subkey: UInt32) -> UInt32 {
        let sum = x &+ subkey
        var sub: UInt32 = 0
        for n in 0..<8 {
            let nibble = Int((sum >> (n * 4)) & 0xF)
            sub |= UInt32(sBox[n][nibble]) << (n * 4)
        }
        return (sub << 11) | (sub >> 21)
    }

    static func encryptBlock(lo: UInt32, hi: UInt32, keys: [UInt32]) -> (UInt32, UInt32) {
        var n1 = lo
        var n2 = hi

        // Расписание индексов ключей для 32 раундов
        let schedule: [Int] = [
            0, 1, 2, 3, 4, 5, 6, 7,   // раунды  1–8
            0, 1, 2, 3, 4, 5, 6, 7,   // раунды  9–16
            0, 1, 2, 3, 4, 5, 6, 7,   // раунды 17–24
            7, 6, 5, 4, 3, 2, 1, 0    // раунды 25–32
        ]

        for ki in schedule {
            let f   = roundFunction(n1, subkey: keys[ki])
            let tmp = n2 ^ f
            n2 = n1
            n1 = tmp
        }

        return (n2, n1)
    }

    static func bytesToBlock(_ b: [UInt8]) -> (UInt32, UInt32) {
        let lo = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
        let hi = UInt32(b[4]) | UInt32(b[5]) << 8 | UInt32(b[6]) << 16 | UInt32(b[7]) << 24
        return (lo, hi)
    }

    static func blockToBytes(lo: UInt32, hi: UInt32) -> [UInt8] {
        [
            UInt8(lo & 0xFF),         UInt8((lo >> 8)  & 0xFF),
            UInt8((lo >> 16) & 0xFF), UInt8((lo >> 24) & 0xFF),
            UInt8(hi & 0xFF),         UInt8((hi >> 8)  & 0xFF),
            UInt8((hi >> 16) & 0xFF), UInt8((hi >> 24) & 0xFF)
        ]
    }

    static func gamma(data: [UInt8], keys: [UInt32], iv: [UInt8]) -> [UInt8] {
        precondition(iv.count == 8, "синхропосылка должна быть 8 байт")

        // Шифруем синхропосылку → начальное состояние счётчика гаммы
        let (ivLo, ivHi) = bytesToBlock(iv)
        let (g0Lo, g0Hi) = encryptBlock(lo: ivLo, hi: ivHi, keys: keys)

        var cLo = g0Lo
        var cHi = g0Hi

        var result = [UInt8]()
        result.reserveCapacity(data.count)

        var offset = 0
        while offset < data.count {
            cLo = cLo &+ delta1
            cHi = cHi &+ delta2

            let (gLo, gHi) = encryptBlock(lo: cLo, hi: cHi, keys: keys)
            let gammaBlock  = blockToBytes(lo: gLo, hi: gHi)

            let blockLen = min(8, data.count - offset)
            for i in 0..<blockLen {
                result.append(data[offset + i] ^ gammaBlock[i])
            }
            offset += 8
        }
        return result
    }

    static func deriveKey(from password: String) -> [UInt8] {
        let base = Data(password.utf8)
        let h1   = Array(Insecure.SHA1.hash(data: base))
        let h2   = Array(Insecure.SHA1.hash(data: base + Data("key2".utf8)))
        return Array((h1 + h2).prefix(32))
    }

    static func deriveIV(from password: String) -> [UInt8] {
        Array(Insecure.SHA1.hash(data: Data(("gost_iv_" + password).utf8)).prefix(8))
    }
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
        let key  = GOST28147.deriveKey(from: password)
        let iv   = GOST28147.deriveIV(from: password)

        appendLog("------------------------")
        appendLog("Пароль: «\(password)»")
        appendLog("SHA-1  → \(sha1Text)")
        appendLog("Сид ЛКГ (8 байт SHA-1): 0x\(String(format: "%016X", seed))")
        appendLog("ГОСТ ключ (256 бит):")
        appendLog("  \(key.map { String(format: "%02x", $0) }.joined())")
        appendLog("ГОСТ IV  (64 бит): \(iv.map { String(format: "%02x", $0) }.joined())")
    }

    // ── Файловые операции ──────────────────────────────────────

    /// Устанавливает входной файл и отображает его имя
    func setInputURL(_ url: URL) {
        inputURL      = url
        inputFileName = url.lastPathComponent
        appendLog("Входной файл: \(url.lastPathComponent)")
    }

    /// Шифрует или дешифрует файл алгоритмом ГОСТ 28147-89 (режим гаммирования).
    /// Режим симметричен: operationName используется только для журнала.
    func processFile(outputURL: URL, operationName: String) async {
        guard !password.isEmpty else { appendLog("⚠ Введите пароль"); return }
        guard let inputURL        else { appendLog("⚠ Входной файл не выбран"); return }

        outputFileName = outputURL.lastPathComponent
        isWorking      = true
        progressValue  = 0.0
        statusText     = "\(operationName)…"

        appendLog("------------------------")
        appendLog("\(operationName) [ГОСТ, режим гаммирования]")
        appendLog("  Вход:  \(inputURL.lastPathComponent)")
        appendLog("  Выход: \(outputURL.lastPathComponent)")

        do {
            let inputData  = try Data(contentsOf: inputURL)
            let totalBytes = inputData.count
            let inputBytes = [UInt8](inputData)
            appendLog("  Размер: \(totalBytes) байт (\(String(format: "%.2f", Double(totalBytes) / 1024)) КБ)")

            // Захватываем пароль до выхода из MainActor-контекста
            let pwd = password

            let outputBytes: [UInt8] = await Task.detached(priority: .userInitiated) {
                let keyBytes = GOST28147.deriveKey(from: pwd)
                let iv       = GOST28147.deriveIV(from: pwd)
                let keys     = GOST28147.keySchedule(from: keyBytes)
                return GOST28147.gamma(data: inputBytes, keys: keys, iv: iv)
            }.value

            try Data(outputBytes).write(to: outputURL)

            progressValue = 1.0
            statusText    = "\(operationName) завершено"
            appendLog("  Выходной размер: \(outputBytes.count) байт")
            appendLog("Готово")

        } catch {
            statusText = "Ошибка"
            appendLog("\(error.localizedDescription)")
        }

        isWorking = false
    }

    // ── Журнал ─────────────────────────────────────────────────

    func appendLog(_ msg: String) {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
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
            .navigationTitle("Лаб 4 — ГОСТ 28147-89, вариант 6")
        }
        .frame(minWidth: 820, minHeight: 540)
    }

    // ── Левая панель ───────────────────────────────────────────

    private var leftPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Секция: пароль и SHA-1
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

                // Секция: справка по алгоритму
                GroupBox(label: Label("Алгоритм", systemImage: "cpu")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("ГОСТ 28147-89", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.callout.bold())
                        Group {
                            Text("• Блок: 64 бит, ключ: 256 бит")
                            Text("• S-блоки: CryptoPro A")
                            Text("• 32 раунда, сеть Фейстеля")
                            Text("• Режим: гаммирование")
                            Text("• Симметричен: шифр = дешифр")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Секция: файл и запуск
                GroupBox(label: Label("Операция", systemImage: "doc.fill")) {
                    VStack(alignment: .leading, spacing: 12) {

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Входной файл:").font(.caption).foregroundStyle(.secondary)
                                Text(vm.inputFileName)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(vm.inputFileName == "Файл не выбран" ? .secondary : .primary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button("Выбрать…") { pickInput() }.controlSize(.small)
                        }

                        if vm.outputFileName != "Файл не выбран" {
                            Divider()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Файл результата:").font(.caption).foregroundStyle(.secondary)
                                Text(vm.outputFileName)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(2)
                            }
                        }

                        Divider()

                        // Переключатель для наглядности (алгоритм симметричен)
                        Picker("", selection: $mode) {
                            ForEach(CipherMode.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        // Кнопка запуска
                        Button { pickOutputAndRun() } label: {
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

                // Секция: прогресс
                GroupBox(label: Label("Состояние", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        if vm.isWorking {
                            ProgressView(value: vm.progressValue).progressViewStyle(.linear)
                            Text("\(Int(vm.progressValue * 100))%  —  \(vm.statusText)")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(vm.statusText).font(.caption).foregroundStyle(.secondary)
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

    // ── Правая панель: журнал ──────────────────────────────────

    private var rightPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Журнал", systemImage: "doc.text.magnifyingglass")
                    .font(.headline).padding(12)
                Spacer()
                Button("Очистить") { vm.clearLog() }
                    .font(.caption).padding(.trailing, 12)
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

    // ── Вспомогательные функции ────────────────────────────────

    /// Диалог выбора входного файла
    private func pickInput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = true
        panel.canChooseDirectories    = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            vm.setInputURL(url)
        }
    }

    /// Диалог выбора выходного файла и запуск обработки
    private func pickOutputAndRun() {
        guard let inputURL = vm.inputURL else { return }
        let panel  = NSSavePanel()
        let suffix = mode == .encrypt ? "_enc" : "_dec"
        let base   = inputURL.deletingPathExtension().lastPathComponent
        let ext    = inputURL.pathExtension.isEmpty ? "bin" : inputURL.pathExtension
        panel.nameFieldStringValue = "\(base)\(suffix).\(ext)"

        if panel.runModal() == .OK, let outURL = panel.url {
            Task { await vm.processFile(outputURL: outURL, operationName: mode.rawValue) }
        }
    }
}

#Preview { ContentView() }
