# Лабораторная работа 4 — Эль-Гамаль

## Содержание
1. [Теоретическая база](#теоретическая-база)
2. [Алгоритм Эль-Гамаля](#алгоритм-эль-гамаля)
   - [Тест Миллера–Рабина](#тест-миллеррабина)
   - [Генерация ключей](#генерация-ключей)
   - [Шифрование и расшифрование](#шифрование-и-расшифрование)

---

## Теоретическая база

**Эль-Гамаль** — асимметричная криптосистема, основанная на вычислительной сложности задачи дискретного логарифмирования. Используется для шифрования произвольного текста блоками.

---

## Алгоритм Эль-Гамаля

Асимметричная криптосистема, стойкость которой основана на сложности задачи **дискретного логарифмирования** в группе по простому модулю.

### Математическая основа

- Выбирается большое простое число `p` и генератор `g`
- Закрытый ключ: случайное `x < p`
- Открытый ключ: `y = g^x mod p`
- **Шифрование**: выбирается случайное `k`, вычисляется `c1 = g^k mod p`, `c2 = m · y^k mod p`
- **Расшифрование**: `m = c2 · (c1^x)⁻¹ mod p`

---

### Структуры данных

Открытый ключ хранит тройку `(p, g, y)`, закрытый — `(p, g, x)`. Каждый зашифрованный блок — пара `(c1, c2)`.

```swift
struct EGPublicKey  { let p, g, y: BigUInt }
struct EGPrivateKey { let p, g, x: BigUInt }
struct EGKeyPair    { let pub: EGPublicKey; let priv: EGPrivateKey }
struct EGBlock      { let c1: BigUInt; let c2: BigUInt }
```

---

### Быстрое возведение в степень по модулю

Все операции Эль-Гамаля сводятся к `base^exp mod mod`. Используется метод двоичного возведения: на каждом шаге экспонента сдвигается вправо, результат накапливается умножением только на нечётных битах.

```swift
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
```

---

### Тест Миллера–Рабина

Для генерации больших простых чисел используется вероятностный тест простоты. Сначала число проверяется пробным делением на малые простые (просеивание), затем запускается основной тест с `rounds=20` итерациями.

```swift
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
```

При 20 раундах вероятность ложноположительного результата не превышает `4⁻²⁰ ≈ 10⁻¹²`.

Просеивание отсекает очевидно составные числа делением на список малых простых — это быстрее, чем сразу запускать полный тест.

```swift
private let smallPrimes: [UInt32] = [
    3,5,7,11,13,17,19,23,29,31,37,41,43,47,53,59,61,67,71,73,
    79,83,89,97,101,103,107,109,113,127,131,137,139,149,151,
    157,163,167,173,179,181,191,193,197,199,211,223,227,229,
    233,239,241,251
]

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
```

---

### Генерация ключей

Простое число нужной разрядности генерируется перебором случайных нечётных чисел с проверкой через тест Миллера–Рабина.

```swift
func generatePrime(bits: Int) -> BigUInt {
    while true {
        let c = randomOddBigUInt(bits: bits)
        if isProbablePrime(c) { return c }
    }
}
```

Затем выбираются случайные `g` и `x`, и вычисляется открытый ключ `y = g^x mod p`.

```swift
func generateKeyPair(bits: Int) -> EGKeyPair {
    let p = generatePrime(bits: bits)
    let g = randomBigUInt(in: BigUInt(2), p - BigUInt(2))
    let x = randomBigUInt(in: BigUInt(2), p - BigUInt(2))
    let y = modPow(g, x, p)
    return EGKeyPair(pub: EGPublicKey(p: p, g: g, y: y),
                     priv: EGPrivateKey(p: p, g: g, x: x))
}
```

---

### Шифрование и расшифрование

Текст разбивается на блоки, размер которых определяется разрядностью `p` (чтобы каждый блок гарантированно был меньше `p`). Каждый блок шифруется независимо с новым случайным `k`.

```swift
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
```

Обратное по модулю вычисляется через **малую теорему Ферма**: `s⁻¹ = s^(p-2) mod p` (работает только для простого `p`).

Для шифрования и расшифрования целого текста он переводится в байты, нарезается на блоки нужного размера и каждый блок обрабатывается независимо.

```swift
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
```

---

## Итог

| Компонент | Назначение |
|---|---|
| Тест Миллера–Рабина | Генерация больших простых чисел для Эль-Гамаля |
| Эль-Гамаль | Асимметричное шифрование текста по открытому ключу |
