import SwiftUI
import CommonCrypto  

@MainActor
final class RandomnessViewModel: ObservableObject {
    
    @Published var bitSequence: [UInt8] = []
    @Published var lengthText: String = "100000"            // по умолчанию
    @Published var seedText: String = "123456789"          // сид
    @Published var selectedGenerator: GeneratorType = .systemRandom
    @Published var status: String = "Запущен"
    @Published var isWorking = false
    @Published var resultText: String = ""
    
    enum GeneratorType: String, CaseIterable, Identifiable {
        case systemRandom = "Генерация"
        case parkMiller   = "Генератор Парка-Миллера "
        case bbs          = "Генератор BBS"
        case fips186      = "FIPS-186"
        
        var id: String { rawValue }
    }
    
    var length: Int {
        Int(lengthText) ?? 100_000
    }
    
    func generateRandomSequence() async {
        guard let n = Int(lengthText), n >= 10000 else {
            resultText = "Длина должна быть числом ≥ 10 000"
            return
        }
        
        isWorking = true
        status = "Создаем последовательность (\(selectedGenerator.rawValue))..."
        defer {
            isWorking = false
            status = "Готово"
        }
        
        var bits: [UInt8] = []
        bits.reserveCapacity(n)
        
        switch selectedGenerator {
        case .systemRandom:
            for _ in 0..<n {
                bits.append(UInt8.random(in: 0...1))
            }
            
        case .parkMiller:
            guard let seedNum = Int64(seedText), seedNum > 0 else {
                resultText = "Некорректный seed для Park-Miller (должен быть положительным целым)"
                return
            }
            let generator = ParkMillerGenerator(seed: seedNum)
            for _ in 0..<n {
                bits.append(generator.nextBit())
            }
            
        case .bbs:
            guard let seedNum = UInt64(seedText), seedNum > 0 else {
                resultText = "Некорректный seed для BBS (должен быть положительным целым)"
                return
            }
            let generator = BBSGenerator(seed: seedNum)
            for _ in 0..<n {
                bits.append(generator.nextBit())
            }
            
        case .fips186:
            guard let seedData = seedText.data(using: .utf8), !seedData.isEmpty else {
                resultText = "Введите seed (любой текст)"
                return
            }
            let generator = FIPS186Generator(seed: seedData)
            bits = generator.generateBits(count: n)
        }
        
        bitSequence = bits
        
        let preview = bits.prefix(200).map(String.init).joined()
        resultText = """
        Сгенерировано \(n) бит с помощью \(selectedGenerator.rawValue)
        Seed: \(seedText)
        
        Первые 200 бит:
        \(preview)
        ...
        """
        status = "Последовательность готова (\(n) бит)"
    }
    
    // Загрузка из файла
    func loadFromFile(url: URL) async {
        isWorking = true
        status = "Чтение из файла"
        defer { isWorking = false }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
            
            let bits = content.compactMap { char -> UInt8? in
                switch char {
                case "0": return 0
                case "1": return 1
                default:  return nil
                }
            }
            
            if bits.isEmpty {
                resultText = "В файле не найдено корректных символов 0 и 1"
                status = "Ошибка загрузки"
                return
            }
            
            bitSequence = bits
            lengthText = "\(bits.count)"
            
            let preview = bits.prefix(200).map(String.init).joined()
            resultText = """
            Загружено \(bits.count) бит из файла:
            \(preview)
            ...
            """
            status = "Файл успешно загружен"
        } catch {
            resultText = "Не удалось прочитать файл:\n\(error.localizedDescription)"
            status = "Ошибка"
        }
    }
    
    // Сохранение в файл
    func saveToFile(url: URL) async {
        guard !bitSequence.isEmpty else {
            resultText = "Нет данных для сохранения"
            return
        }
        
        isWorking = true
        status = "Сохранение файла..."
        defer { isWorking = false }
        
        let text = bitSequence.map(String.init).joined()
        
        do {
            try text.write(to: url, atomically: false, encoding: .utf8)
            resultText += "\n\nПоследовательность сохранена в:\n\(url.path)"
            status = "Сохранено"
        } catch {
            resultText += "\n\nОшибка при сохранении:\n\(error.localizedDescription)"
        }
    }
    
    // Тесты
    func runTests() async {
        guard !bitSequence.isEmpty else {
            resultText = "Сначала сгенерируйте или загрузите последовательность"
            return
        }
        
        isWorking = true
        status = "Выполнение тестов..."
        resultText = "Тестирование последовательности длиной \(bitSequence.count) бит (генератор: \(selectedGenerator.rawValue))\n\n"
        
        defer {
            isWorking = false
            status = "Тестирование завершено"
        }
        
        let freq = frequencyTest()
        resultText += """
        1. Частотный тест (Monobit test)
           Статистика S = \(String(format: "%.6f", freq.s))
           Порог     = 1.82138636
           Результат = \(freq.passed ? "Пройден " : "НЕ ПРОЙДЕН ")
        
        """
        
        if !freq.passed {
            resultText += "\nПоследовательность неравномерна → остальные тесты не выполняются\n"
            return
        }
        
        let runs = runsTest()
        resultText += """
        2. Тест на последовательность одинаковых бит (Runs test)
           Vₙ        = \(runs.vn)
           Статистика = \(String(format: "%.6f", runs.s))
           Порог      = 1.82138636
           Результат  = \(runs.passed ? "Пройден" : "НЕ пройден")
        
        """
        
        let excursions = randomExcursionsVariantTest()
        resultText += """
        3. Расширенный тест на произвольные отклонения (Random Excursions Variant)
           Проверено состояний: 18 (от -9 до -1 и от 1 до 9)
           Кол-во проваленных состояний: \(excursions.failedCount)
           Результат: \(excursions.passed ? "Пройден полностью" : "Не пройден")
        
        """
        
        if !excursions.failedStates.isEmpty {
            resultText += "Проваленные состояния: " + excursions.failedStates.sorted().map { "\($0)" }.joined(separator: ", ") + "\n"
        }
    }
    
    
    private func frequencyTest() -> (passed: Bool, s: Double) {
        let n = Double(bitSequence.count)
        var sum = 0.0
        for bit in bitSequence {
            sum += (bit == 1) ? 1.0 : -1.0
        }
        let statistic = abs(sum) / sqrt(n)
        let threshold = 1.82138636
        return (statistic <= threshold, statistic)
    }
    
    private func runsTest() -> (passed: Bool, vn: Int, s: Double) {
        let n = Double(bitSequence.count)
        let ones = bitSequence.reduce(0) { $0 + Int($1) }
        let pi = Double(ones) / n
        var runs = 1
        for i in 1..<bitSequence.count {
            if bitSequence[i] != bitSequence[i - 1] {
                runs += 1
            }
        }
        let vn = runs
        let numerator   = abs(Double(vn) - 2.0 * n * pi * (1.0 - pi))
        let denominator = 2.0 * sqrt(2.0 * n) * pi * (1.0 - pi)
        let statistic   = numerator / denominator
        let threshold = 1.82138636
        return (statistic <= threshold, vn, statistic)
    }
    
    private func randomExcursionsVariantTest() -> (passed: Bool, failedCount: Int, failedStates: Set<Int>) {
        let n = bitSequence.count
        var partialSums = [Int]()
        partialSums.reserveCapacity(n + 2)
        partialSums.append(0)
        var current = 0
        for bit in bitSequence {
            current += (bit == 1) ? 1 : -1
            partialSums.append(current)
        }
        partialSums.append(0)
        
        let zerosCount = partialSums.filter { $0 == 0 }.count
        let L = zerosCount - 1
        
        if L <= 0 {
            return (false, 18, Set(-9...9).subtracting([0]))
        }
        
        var visits = [Int: Int]()
        for j in -9...9 where j != 0 {
            visits[j] = 0
        }
        
        for s in partialSums {
            if abs(s) <= 9 && s != 0 {
                visits[s, default: 0] += 1
            }
        }
        
        var failed = Set<Int>()
        let threshold = 1.82138636
        
        for j in -9...9 where j != 0 {
            guard let xi = visits[j] else { continue }
            let absJ = Double(abs(j))
            let denom = sqrt(2.0 * Double(L) * (4.0 * absJ - 2.0))
            if denom <= 0 { continue }
            let yj = abs(Double(xi) - Double(L)) / denom
            if yj > threshold {
                failed.insert(j)
            }
        }
        
        return (failed.isEmpty, failed.count, failed)
    }
}

//генератор парка миллера
final class ParkMillerGenerator {
    private var state: Int64
    private let a: Int64 = 16807          // 7^5
    private let m: Int64 = 2_147_483_647  // 2^31 - 1
    
    init(seed: Int64) {
        self.state = seed % m
        if self.state <= 0 { self.state = 1 }
    }
    
    func nextBit() -> UInt8 {
        let q: Int64 = 127773
        let r: Int64 = 2836
        let hi = state / q
        let lo = state % q
        var t = a * lo - r * hi
        if t <= 0 { t += m }
        state = t
        return UInt8(state & 1)
    }
}

//ббс генератор
final class BBSGenerator {
    private var state: UInt64
    private let modulus: UInt64
    
    init(seed: UInt64) {
        let p: UInt64 = 383
        let q: UInt64 = 503
        modulus = p * q
        
        state = seed % modulus
        if state == 0 { state = 1 }
    }
    
    func nextBit() -> UInt8 {
        state = (state * state) % modulus
        return UInt8(state & 1)
    }
}
//генератор фипс186
final class FIPS186Generator {
    private var x: Data

    init(seed: Data) {
        var seedData = seed
        if seedData.count < 20 {
            seedData = Data(repeating: 0, count: 20 - seedData.count) + seedData
        }
        self.x = seedData.prefix(20)
    }

    func generateBits(count: Int) -> [UInt8] {
        var bits: [UInt8] = []
        bits.reserveCapacity(count)
        var currentX = x

        while bits.count < count {
            let xval = currentX
            var digest = Data(count: Int(CC_SHA1_DIGEST_LENGTH))
            digest.withUnsafeMutableBytes { dPtr in
                xval.withUnsafeBytes { xPtr in
                    _ = CC_SHA1(
                        xPtr.baseAddress,
                        CC_LONG(xval.count),
                        dPtr.baseAddress!
                    )
                }
            }
            currentX = addMod160(addMod160(currentX, digest), makeOne())
            for byte in digest {
                for i in 0..<8 {
                    if bits.count >= count { return bits }
                    let bit = (byte >> i) & 1
                    bits.append(UInt8(bit))
                }
            }
        }

        return bits
    }

    
    private func addMod160(_ a: Data, _ b: Data) -> Data {
        precondition(a.count == 20 && b.count == 20)
        var result = Data(count: 20)
        var carry: UInt16 = 0

        // Идём с младшего байта (индекс 19) к старшему (индекс 0)
        for i in stride(from: 19, through: 0, by: -1) {
            let sum = UInt16(a[i]) + UInt16(b[i]) + carry
            result[i] = UInt8(sum & 0xFF)
            carry = sum >> 8
        }
        return result
    }

    private func makeOne() -> Data {
        var d = Data(count: 20)
        d[19] = 0x01
        return d
    }
}

struct ContentView: View {
    
    @StateObject private var viewModel = RandomnessViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                
                Picker("Генератор", selection: $viewModel.selectedGenerator) {
                    ForEach(RandomnessViewModel.GeneratorType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                
                HStack {
                    Text("Длина последовательности (бит):")
                    TextField("≥ 10000", text: $viewModel.lengthText)
                        .frame(width: 140)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: Binding(
                        get: { Int(viewModel.lengthText) ?? 100000 },
                        set: { viewModel.lengthText = String(max(10000, $0)) }
                    ), in: 10000...1_000_000, step: 10000)
                }
                
                HStack {
                    Text("Seed / Ключ:")
                    TextField("Введите seed", text: $viewModel.seedText)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack(spacing: 20) {
                    Button("Сгенерировать") {
                        Task { await viewModel.generateRandomSequence() }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Запустить тесты") {
                        Task { await viewModel.runTests() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                
                HStack(spacing: 20) {
                    Button("Загрузить .txt") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.plainText]
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        if panel.runModal() == .OK, let url = panel.url {
                            Task { await viewModel.loadFromFile(url: url) }
                        }
                    }
                    
                    Button("Сохранить .txt") {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.plainText]
                        panel.nameFieldStringValue = "bits_\(viewModel.bitSequence.count)_\(viewModel.selectedGenerator.rawValue).txt"
                        if panel.runModal() == .OK, let url = panel.url {
                            Task { await viewModel.saveToFile(url: url) }
                        }
                    }
                }
                
                if viewModel.isWorking {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
                
                Text(viewModel.status)
                    .foregroundStyle(.secondary)
                
                ScrollView {
                    Text(viewModel.resultText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
            }
            .padding()
            .navigationTitle("Лабораторная №2 — Генераторы ПСЧ")
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}

#Preview {
    ContentView()
}
