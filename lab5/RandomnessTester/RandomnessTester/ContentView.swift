//
//  ContentView.swift
//  Лабораторная работа №5 — Алгоритм Эль-Гамаля + Тест Рабина–Миллера
//

import SwiftUI
import Security

// Нужно для работы с большими битами
struct BigUInt: Comparable, Equatable, Hashable, CustomStringConvertible {
    var words: [UInt32]
    init(words: [UInt32]) { self.words = words; trim() }
    init(_ v: UInt64) {
        if v == 0 { words = [] }
        else if v <= 0xFFFF_FFFF { words = [UInt32(v)] }
        else { words = [UInt32(v & 0xFFFF_FFFF), UInt32(v >> 32)] }
    }
    init(_ v: UInt32) { words = v == 0 ? [] : [v] }
    init(_ v: Int) { precondition(v >= 0); self.init(UInt64(v)) }

    static let zero = BigUInt(words: [])
    static let one  = BigUInt(words: [1])

    mutating func trim() { while !words.isEmpty && words.last == 0 { words.removeLast() } }

    var isZero: Bool { words.isEmpty }
    var isOne: Bool  { words == [1] }
    var isEven: Bool { words.isEmpty || words[0] & 1 == 0 }

    var bitWidth: Int {
        guard let top = words.last else { return 0 }
        return (words.count - 1) * 32 + (32 - top.leadingZeroBitCount)
    }

    func bit(_ i: Int) -> Bool {
        let (wi, bi) = (i / 32, i % 32)
        guard wi < words.count else { return false }
        return (words[wi] >> bi) & 1 == 1
    }

    var description: String {
        isZero ? "0" : words.reversed().map { String(format: "%08x", $0) }.joined()
    }
}

// Сравнение
func < (lhs: BigUInt, rhs: BigUInt) -> Bool {
    if lhs.words.count != rhs.words.count { return lhs.words.count < rhs.words.count }
    for i in stride(from: lhs.words.count - 1, through: 0, by: -1) {
        if lhs.words[i] != rhs.words[i] { return lhs.words[i] < rhs.words[i] }
    }
    return false
}

// Сложение
func + (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
    let n = max(lhs.words.count, rhs.words.count)
    var out = [UInt32](); out.reserveCapacity(n + 1)
    var carry: UInt64 = 0
    for i in 0..<n {
        let s = (i < lhs.words.count ? UInt64(lhs.words[i]) : 0) +
                (i < rhs.words.count ? UInt64(rhs.words[i]) : 0) + carry
        out.append(UInt32(s & 0xFFFF_FFFF))
        carry = s >> 32
    }
    if carry > 0 { out.append(1) }
    return BigUInt(words: out)
}

// Вычитание для BIG INT
func - (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
    var out = [UInt32](); out.reserveCapacity(lhs.words.count)
    var borrow: Int64 = 0
    for i in 0..<lhs.words.count {
        var d = Int64(lhs.words[i]) -
                (i < rhs.words.count ? Int64(rhs.words[i]) : 0) - borrow
        if d < 0 { d += (1 << 32); borrow = 1 } else { borrow = 0 }
        out.append(UInt32(d & 0xFFFF_FFFF))
    }
    return BigUInt(words: out)
}

// Умножение
func * (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
    guard !lhs.isZero, !rhs.isZero else { return .zero }
    var out = [UInt32](repeating: 0, count: lhs.words.count + rhs.words.count)
    for i in 0..<lhs.words.count {
        var carry: UInt64 = 0
        for j in 0..<rhs.words.count {
            let p = UInt64(lhs.words[i]) * UInt64(rhs.words[j]) +
                    UInt64(out[i + j]) + carry
            out[i + j] = UInt32(p & 0xFFFF_FFFF)
            carry = p >> 32
        }
        var k = i + rhs.words.count
        while carry > 0 {
            let s = UInt64(out[k]) + carry
            out[k] = UInt32(s & 0xFFFF_FFFF)
            carry = s >> 32
            k += 1
        }
    }
    return BigUInt(words: out)
}

// Сдвиги
func << (lhs: BigUInt, sh: Int) -> BigUInt {
    guard sh > 0, !lhs.isZero else { return lhs }
    let (wSh, bSh) = (sh / 32, sh % 32)
    var out = [UInt32](repeating: 0, count: lhs.words.count + wSh + 1)
    for i in 0..<lhs.words.count {
        let v = UInt64(lhs.words[i]) << bSh
        out[i + wSh] |= UInt32(v & 0xFFFF_FFFF)
        out[i + wSh + 1] |= UInt32(v >> 32)
    }
    return BigUInt(words: out)
}

func >> (lhs: BigUInt, sh: Int) -> BigUInt {
    guard sh > 0, !lhs.isZero else { return lhs }
    let (wSh, bSh) = (sh / 32, sh % 32)
    guard wSh < lhs.words.count else { return .zero }
    var out = [UInt32]()
    for i in wSh..<lhs.words.count {
        var w = lhs.words[i] >> bSh
        if bSh > 0, i + 1 < lhs.words.count { w |= lhs.words[i + 1] << (32 - bSh) }
        out.append(w)
    }
    return BigUInt(words: out)
}

// Деление
func divmod(_ a: BigUInt, _ b: BigUInt) -> (BigUInt, BigUInt) {
    precondition(!b.isZero)
    if a < b { return (.zero, a) }
    if b.isOne { return (a, .zero) }
    let shift = a.bitWidth - b.bitWidth
    var d = b << shift
    var r = a, q = BigUInt.zero
    for _ in (0...shift).reversed() {
        q = q << 1
        if r >= d { r = r - d; q = q + .one }
        d = d >> 1
    }
    return (q, r)
}
func % (lhs: BigUInt, rhs: BigUInt) -> BigUInt { divmod(lhs, rhs).1 }
func / (lhs: BigUInt, rhs: BigUInt) -> BigUInt { divmod(lhs, rhs).0 }

// MARK: – Вспомогательные функции
private func secureBytes(_ n: Int) -> [UInt8] {
    var b = [UInt8](repeating: 0, count: n)
    _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
    return b
}

func bytesToBigUInt(_ bytes: [UInt8]) -> BigUInt {
    var words = [UInt32]()
    var i = bytes.count
    while i > 0 {
        let start = max(0, i - 4)
        var w: UInt32 = 0
        for j in start..<i { w = (w << 8) | UInt32(bytes[j]) }
        words.append(w)
        i = start
    }
    return BigUInt(words: words)
}

func bigUIntToBytes(_ n: BigUInt, length: Int? = nil) -> [UInt8] {
    guard !n.isZero else { return [UInt8](repeating: 0, count: length ?? 1) }
    var bytes = [UInt8]()
    for word in n.words.reversed() {
        bytes.append(UInt8((word >> 24) & 0xFF))
        bytes.append(UInt8((word >> 16) & 0xFF))
        bytes.append(UInt8((word >> 8) & 0xFF))
        bytes.append(UInt8(word & 0xFF))
    }
    while bytes.first == 0 && !bytes.isEmpty { bytes.removeFirst() }
    if let length { while bytes.count < length { bytes.insert(0, at: 0) } }
    return bytes
}

func randomOddBigUInt(bits: Int) -> BigUInt {
    let byteCount = (bits + 7) / 8
    var bytes = secureBytes(byteCount)
    let excess = byteCount * 8 - bits
    bytes[0] = (bytes[0] & UInt8(0xFF >> excess)) | UInt8(1 << (7 - excess))
    bytes[byteCount - 1] |= 0x01
    return bytesToBigUInt(bytes)
}

func randomBigUInt(in lo: BigUInt, _ hi: BigUInt) -> BigUInt {
    precondition(lo <= hi)
    if lo == hi { return lo }
    let span = hi - lo + .one
    let byteCount = (span.bitWidth + 7) / 8 + 4
    return bytesToBigUInt(secureBytes(byteCount)) % span + lo
}

    // Рабин Миллер Алгоритм
    private let smallPrimes: [UInt32] = [3,5,7,11,13,17,19,23,29,31,37,41,43,47,53,59,61,67,71,73,79,83,89,97,101,103,107,109,113,127,131,137,139,149,151,157,163,167,173,179,181,191,193,197,199,211,223,227,229,233,239,241,251]

    private func passesSieve(_ n: BigUInt) -> Bool {
        for sp in smallPrimes {
            if n == BigUInt(UInt64(sp)) { return true }
            if mod32(n, sp) == 0 { return false }
        }
        return true
    }

    private func mod32(_ n: BigUInt, _ m: UInt32) -> UInt32 {
        let base: UInt64 = (UInt64(1) << 32) % UInt64(m)
        var rem: UInt64 = 0
        for w in n.words.reversed() {
            rem = (rem * base + UInt64(w)) % UInt64(m)
        }
        return UInt32(rem)
    }

    func modPow(_ base: BigUInt, _ exp: BigUInt, _ mod: BigUInt) -> BigUInt {
        guard !mod.isOne else { return .zero }
        var result = BigUInt.one
        var b = base % mod
        var e = exp
        while !e.isZero {
            if e.bit(0) { result = (result * b) % mod }
            e = e >> 1
            b = (b * b) % mod
        }
        return result
    }

    func isProbablePrime(_ n: BigUInt, rounds: Int = 20) -> Bool {
        if n < BigUInt(2) { return false }
        if n == BigUInt(2) || n == BigUInt(3) { return true }
        if n.isEven { return false }
        if !passesSieve(n) { return false }

        var d = n - .one; var r = 0
        while d.isEven { d = d >> 1; r += 1 }

        let nMinus1 = n - .one
        for _ in 0..<rounds {
            let a = randomBigUInt(in: BigUInt(2), nMinus1 - .one)
            var x = modPow(a, d, n)
            if x == .one || x == nMinus1 { continue }
            var composite = true
            for _ in 0..<(r - 1) {
                x = (x * x) % n
                if x == nMinus1 { composite = false; break }
            }
            if composite { return false }
        }
        return true
    }

    //Генерация простых чисел
    func generatePrime(bits: Int) -> BigUInt {
        while true {
            let c = randomOddBigUInt(bits: bits)
            if isProbablePrime(c) { return c }
        }
    }

    //Эль-Гамаль
    struct EGPublicKey  { let p, g, y: BigUInt }
    struct EGPrivateKey { let p, g, x: BigUInt }
    struct EGKeyPair    { let pub: EGPublicKey; let priv: EGPrivateKey }

    func generateKeyPair(bits: Int) -> EGKeyPair {
        let p = generatePrime(bits: bits)
        let g = randomBigUInt(in: BigUInt(2), p - BigUInt(2))
        let x = randomBigUInt(in: BigUInt(2), p - BigUInt(2))
        let y = modPow(g, x, p)
        return EGKeyPair(pub: EGPublicKey(p: p, g: g, y: y),
                         priv: EGPrivateKey(p: p, g: g, x: x))
    }

    struct EGBlock { let c1: BigUInt; let c2: BigUInt }

    func egEncryptBlock(_ m: BigUInt, pub: EGPublicKey) -> EGBlock {
        let k  = randomBigUInt(in: BigUInt(2), pub.p - BigUInt(2))
        let c1 = modPow(pub.g, k, pub.p)
        let c2 = (m * modPow(pub.y, k, pub.p)) % pub.p
        return EGBlock(c1: c1, c2: c2)
    }

    func egDecryptBlock(_ b: EGBlock, priv: EGPrivateKey) -> BigUInt {
        let s    = modPow(b.c1, priv.x, priv.p)
        let sInv = modPow(s, priv.p - BigUInt(2), priv.p)
        return (b.c2 * sInv) % priv.p
    }

    func encryptText(_ text: String, pub: EGPublicKey) -> ([EGBlock], Int) {
        let data = [UInt8](text.utf8)
        let bSize = max(1, (pub.p.bitWidth - 1) / 8)
        var blocks = [EGBlock]()
        var i = 0
        while i < data.count {
            let chunk = Array(data[i..<min(i + bSize, data.count)])
            blocks.append(egEncryptBlock(bytesToBigUInt(chunk), pub: pub))
            i += bSize
        }
        return (blocks, data.count)
    }

    func decryptText(_ blocks: [EGBlock], priv: EGPrivateKey, pub: EGPublicKey, totalBytes: Int) -> String {
        let bSize = max(1, (pub.p.bitWidth - 1) / 8)
        var bytes = [UInt8]()
        for (idx, block) in blocks.enumerated() {
            let m = egDecryptBlock(block, priv: priv)
            let len = (idx == blocks.count - 1) ? (totalBytes - idx * bSize) : bSize
            bytes += bigUIntToBytes(m, length: max(1, len))
        }
        return String(bytes: bytes, encoding: .utf8) ?? "<ошибка>"
    }

// UI
@MainActor
final class EGViewModel: ObservableObject {
    @Published var bitsSelection = 128
    @Published var isGenerating = false
    @Published var keyPair: EGKeyPair?

    @Published var plainText = ""
    @Published var cipherDisplay = ""
    @Published var decryptedText = ""
    @Published var statusText = "Ключи не сгенерированы"
    @Published var logText = ""

    private var encryptedBlocks = [EGBlock]()
    private var totalEncBytes = 0

    var hasEncryptedData: Bool { !encryptedBlocks.isEmpty }

    func generateKeys() async {
        isGenerating = true
        statusText = "Генерация ключей…"
        log("Генерация ключей Эль-Гамаля (p = \(bitsSelection) бит)")

        let bits = bitsSelection
        let pair = await Task.detached { generateKeyPair(bits: bits) }.value

        keyPair = pair
        isGenerating = false
        statusText = "Ключи готовы ✓"

        let pub = pair.pub
        log("p (\(pub.p.bitWidth) бит): \(pub.p)")
        log("g (\(pub.g.bitWidth) бит): \(pub.g)")
        log("x (секрет): \(pair.priv.x)")
        log("y: \(pub.y)")
    }

    func encrypt() {
        guard let pair = keyPair, !plainText.isEmpty else { return }
        let (blocks, total) = encryptText(plainText, pub: pair.pub)
        encryptedBlocks = blocks
        totalEncBytes = total
        cipherDisplay = blocks.map { "\($0.c1):\($0.c2)" }.joined(separator: "\n")
        statusText = "Зашифровано"
        log("Зашифровано \(blocks.count) блоков")
    }

    func decrypt() {
        guard let pair = keyPair, !encryptedBlocks.isEmpty else { return }
        decryptedText = decryptText(encryptedBlocks, priv: pair.priv, pub: pair.pub, totalBytes: totalEncBytes)
        statusText = "Дешифровано"
        log(decryptedText == plainText ? "✓ Успешно" : "✗ Ошибка")
    }

    func log(_ msg: String) {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        logText += "[\(df.string(from: Date()))] \(msg)\n"
    }
    func clearLog() { logText = "" }
}

// MARK: – ContentView
struct ContentView: View {
    @StateObject private var vm = EGViewModel()

    var body: some View {
        NavigationStack {
            HSplitView {
                leftPanel.frame(minWidth: 460, maxWidth: 580)
                rightPanel.frame(minWidth: 360)
            }
            .navigationTitle("Лаб 5 — Эль-Гамаль")
        }
        .frame(minWidth: 940, minHeight: 660)
    }

    private var leftPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(label: Label("Алгоритм", systemImage: "cpu")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Эль-Гамаль + Rabin-Miller", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green).font(.callout.bold())
                        Text("• p — случайное простое ≥ 128 бит")
                        Text("• g, x — случайные 2 ≤ … < p")
                        Text("• y = gˣ mod p")
                        Text("• c₁ = gᵏ mod p, c₂ = m·yᵏ mod p")
                        Text("• m = c₂ · (c₁ˣ)⁻¹ mod p")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }

                GroupBox(label: Label("Генерация ключей", systemImage: "key.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Размер p:").font(.caption).foregroundStyle(.secondary)
                            Text("128 бит")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }

                        Button {
                            Task { await vm.generateKeys() }
                        } label: {
                            if vm.isGenerating {
                                HStack { ProgressView().controlSize(.small); Text("Генерация…") }
                            } else {
                                Label("Сгенерировать пару", systemImage: "wand.and.stars")
                            }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(vm.isGenerating)

                        if let kp = vm.keyPair { keyTable(kp) }
                    }.padding(8)
                }

                GroupBox(label: Label("Шифрование", systemImage: "lock.fill")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Открытый текст:").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $vm.plainText)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 80)
                        Button("Зашифровать", systemImage: "lock.fill") { vm.encrypt() }
                            .buttonStyle(.borderedProminent).tint(.blue).controlSize(.large)
                            .disabled(vm.keyPair == nil || vm.plainText.isEmpty)
                        if !vm.cipherDisplay.isEmpty {
                            Divider()
                            ScrollView { Text(vm.cipherDisplay).font(.system(.caption2, design: .monospaced)) }
                                .frame(height: 90)
                        }
                    }.padding(8)
                }

                GroupBox(label: Label("Дешифрование", systemImage: "lock.open.fill")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Дешифровать", systemImage: "lock.open.fill") { vm.decrypt() }
                            .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)
                            .disabled(!vm.hasEncryptedData)
                        if !vm.decryptedText.isEmpty {
                            Divider()
                            Text(vm.decryptedText)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }.padding(8)
                }
            }.padding()
        }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Журнал", systemImage: "doc.text.magnifyingglass").font(.headline)
                Spacer()
                Text(vm.statusText).font(.caption).padding(6).background(.quaternary, in: Capsule())
                Button("Очистить") { vm.clearLog() }.buttonStyle(.borderless).font(.caption)
            }.padding([.top, .horizontal])
            Divider()
            ScrollView {
                Text(vm.logText.isEmpty ? "Журнал пуст…" : vm.logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }.background(Color(nsColor: .textBackgroundColor))
        }
    }

    @ViewBuilder
    private func keyTable(_ kp: EGKeyPair) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ключи").font(.caption.bold())
            ForEach([
                ("p", kp.pub.p.bitWidth, kp.pub.p.description, false),
                ("g", kp.pub.g.bitWidth, kp.pub.g.description, false),
                ("x", kp.priv.x.bitWidth, kp.priv.x.description, true),
                ("y", kp.pub.y.bitWidth, kp.pub.y.description, false)
            ], id: \.0) { name, bits, hex, secret in
                VStack(alignment: .leading, spacing: 2) {
                    HStack { Text(name).bold(); Text("(\(bits) бит)").font(.caption2) }
                    Text(String(hex.prefix(64)) + (hex.count > 64 ? "…" : ""))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(secret ? .orange : .secondary)
                }
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

#Preview { ContentView() }
