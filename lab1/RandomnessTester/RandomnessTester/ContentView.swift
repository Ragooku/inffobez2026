//
//  ContentView.swift
//  RandomnessTester
//
//
//
import SwiftUI

@MainActor
final class RandomnessViewModel: ObservableObject {
    
    @Published var bitSequence: [UInt8] = []            // массив 0 и 1
    @Published var lengthText: String = "100000"
    @Published var status: String = "Запущен"
    @Published var isWorking = false
    @Published var resultText: String = ""
    
    var length: Int {
        Int(lengthText) ?? 100_000 // по умолчанию
    }
    
//случайная последовательность
    func generateRandomSequence() async {
        guard let n = Int(lengthText), n >= 10000 else {
            resultText = "Длина должна быть числом ≥ 10 000"
            return
        }
        
        isWorking = true
        status = "Создаем последовательность..."
        defer {
            isWorking = false
            status = "Готово"
        }
        
        var bits: [UInt8] = []  //выделяем память
        bits.reserveCapacity(n)
        
        for _ in 0..<n { // генерация последовательности
            bits.append(UInt8.random(in: 0...1))
        }
        
        bitSequence = bits
        
        let preview = bits.prefix(200).map(String.init).joined()
        resultText = """
        Сгенерировано \(n) бит (200):
        \(preview)
        ...
        """
        status = "Последовательность готова (\(n) бит)"
    }
    
    // реализация загрузки из текстового документа
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
            
            //проверка на 0 и 1
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
    
  //сохранение в файл .txt
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
    
    // Статус Тестирования
    func runTests() async {
        guard !bitSequence.isEmpty else {
            resultText = "Сначала сгенерируйте или загрузите последовательность"
            return
        }
        
        isWorking = true
        status = "Выполнение тестов..."
        resultText = "Тестирование последовательности длиной \(bitSequence.count) бит\n\n"
        
        defer {
            isWorking = false
            status = "Тестирование завершено"
        }
        
        // вывод частоточного теста
        let freq = frequencyTest()
        resultText += """
        1. Частотный тест (Monobit test)
           Статистика S = \(String(format: "%.6f", freq.s))
           Порог     = 1.82138636
           Результат = \(freq.passed ? "Пройден ✓" : "НЕ ПРОЙДЕН ✗")
        
        """
        
        if !freq.passed {
            resultText += "\nПоследовательность неравномерна → остальные тесты не выполняются\n"
            return
        }
        
        // Вывод сообщения с последовательностью одинаковых бит
        let runs = runsTest()
        resultText += """
        2. Тест на последовательность одинаковых бит (Runs test)
           Vₙ        = \(runs.vn)
           Статистика = \(String(format: "%.6f", runs.s))
           Порог      = 1.82138636
           Результат  = \(runs.passed ? "Пройден" : "Н пройден")
        
        """
        
        // Расширенный тест на произвольные отклонения
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
    
    // Частотный тест
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
    
    // Тест на последовательность
    private func runsTest() -> (passed: Bool, vn: Int, s: Double) {
        let n = Double(bitSequence.count)
        
        // π — доля единиц
        let ones = bitSequence.reduce(0) { $0 + Int($1) }
        let pi = Double(ones) / n
        
        // Подсчёт количества переходов (runs)
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
    
    // Тест на произвольные отклонения
    private func randomExcursionsVariantTest() -> (passed: Bool, failedCount: Int, failedStates: Set<Int>) {
        let n = bitSequence.count
        
        // Кумулятивные суммы 0 -> -1 1->+1
        var partialSums = [Int]()
        partialSums.reserveCapacity(n + 2)
        partialSums.append(0)
        
        var current = 0
        for bit in bitSequence {
            current += (bit == 1) ? 1 : -1
            partialSums.append(current)
        }
        partialSums.append(0)           // S'_{n+1} = 0
        
        // Количество возвращений в 0 (циклов)
        let zerosCount = partialSums.filter { $0 == 0 }.count
        let L = zerosCount - 1          // количество циклов
        
        if L <= 0 {
            return (false, 18, Set(-9...9).subtracting([0]))
        }
        
        // Подсчёт состояний
        var visits = [Int: Int]()
        for j in -9...9 where j != 0 {
            visits[j] = 0
        }
        
        for s in partialSums {
            if let count = visits[s], s != 0 {
                visits[s] = count + 1
            } else if s != 0 && abs(s) <= 9 {
                visits[s] = 1
            }
        }
        
        var failed = Set<Int>()
        let threshold = 1.82138636
        
        for j in -9...9 where j != 0 {
            guard let xi = visits[j] else { continue }
            
            let denom = sqrt(2.0 * Double(L) * (4.0 * Double(abs(j)) - 2.0))
            if denom <= 0 { continue }  // деление на 0
            
            let yj = abs(Double(xi) - Double(L)) / denom
            
            if yj > threshold {
                failed.insert(j)
            }
        }
        
        return (failed.isEmpty, failed.count, failed)
    }
}

//интерфейс
struct ContentView: View {
    
    @StateObject private var viewModel = RandomnessViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                
                // Ввод длины
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
                
                // Кнопки действий
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
                        panel.nameFieldStringValue = "bits_\(viewModel.bitSequence.count).txt"
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
                
                // Результаты
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
            .navigationTitle("Тестирование случайности последовательностей")
        }
        .frame(minWidth: 800, minHeight: 680)
    }
}

#Preview {
    ContentView()
}
