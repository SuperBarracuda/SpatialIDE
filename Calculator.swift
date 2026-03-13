import Foundation

// MARK: - CalculatorDisplay Protocol

public protocol CalculatorDisplay {
    func formatResult(_ value: Double) -> String
    func showError(_ message: String)
}

// MARK: - Calculator

public class Calculator {
    
    private var lastResult: Double = 0.0
    public var history: CalculatorHistory
    
    public init() {
        self.history = CalculatorHistory()
    }
    
    public func add(_ a: Double, _ b: Double) -> Double {
        let result = a + b
        lastResult = result
        history.addEntry("add(\(a), \(b)) = \(result)")
        return result
    }
    
    public func subtract(_ a: Double, _ b: Double) -> Double {
        let result = a - b
        lastResult = result
        history.addEntry("subtract(\(a), \(b)) = \(result)")
        return result
    }
    
    public func multiply(_ a: Double, _ b: Double) -> Double {
        let result = a * b
        lastResult = result
        history.addEntry("multiply(\(a), \(b)) = \(result)")
        return result
    }
    
    public func divide(_ a: Double, _ b: Double) throws -> Double {
        guard b != 0 else {
            throw CalculatorError.divisionByZero
        }
        let result = a / b
        lastResult = result
        history.addEntry("divide(\(a), \(b)) = \(result)")
        return result
    }
    
    public func getLastResult() -> Double {
        return lastResult
    }
}

// MARK: - ScientificCalculator

public class ScientificCalculator: Calculator {
    
    private var angleMode: AngleMode = .radians
    
    public enum AngleMode {
        case radians
        case degrees
    }
    
    public func setAngleMode(_ mode: AngleMode) {
        self.angleMode = mode
    }
    
    public func power(_ base: Double, _ exponent: Double) -> Double {
        let result = pow(base, exponent)
        history.addEntry("power(\(base), \(exponent)) = \(result)")
        return result
    }
    
    public func squareRoot(_ value: Double) throws -> Double {
        guard value >= 0 else {
            throw CalculatorError.negativeSquareRoot
        }
        let result = sqrt(value)
        history.addEntry("squareRoot(\(value)) = \(result)")
        return result
    }
    
    public func factorial(_ n: Int) throws -> Double {
        guard n >= 0 else {
            throw CalculatorError.negativeFactorial
        }
        guard n <= 170 else {
            throw CalculatorError.overflow
        }
        var result: Double = 1.0
        for i in 1...max(n, 1) {
            result *= Double(i)
        }
        history.addEntry("factorial(\(n)) = \(result)")
        return result
    }
    
    public func logarithm(_ value: Double) throws -> Double {
        guard value > 0 else {
            throw CalculatorError.invalidLogarithm
        }
        let result = log(value)
        history.addEntry("logarithm(\(value)) = \(result)")
        return result
    }
}

// MARK: - CalculatorHistory

public class CalculatorHistory {
    
    private var entries: [HistoryEntry] = []
    private let maxEntries: Int
    
    public struct HistoryEntry {
        public let expression: String
        public let timestamp: Date
    }
    
    public init(maxEntries: Int = 100) {
        self.maxEntries = maxEntries
    }
    
    public func addEntry(_ expression: String) {
        let entry = HistoryEntry(expression: expression, timestamp: Date())
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst()
        }
    }
    
    public func getHistory() -> [HistoryEntry] {
        return entries
    }
    
    public func getLastEntry() -> HistoryEntry? {
        return entries.last
    }
    
    public func clearHistory() {
        entries.removeAll()
    }
    
    public var count: Int {
        return entries.count
    }
}

// MARK: - ConsoleDisplay

public class ConsoleDisplay: CalculatorDisplay {
    
    private var precision: Int
    
    public init(precision: Int = 4) {
        self.precision = precision
    }
    
    public func formatResult(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.\(precision)f", value)
    }
    
    public func showError(_ message: String) {
        print("❌ Error: \(message)")
    }
    
    public func setPrecision(_ digits: Int) {
        self.precision = max(0, min(digits, 15))
    }
}

// MARK: - CalculatorError

public enum CalculatorError: Error, CustomStringConvertible {
    case divisionByZero
    case negativeSquareRoot
    case negativeFactorial
    case overflow
    case invalidLogarithm
    
    public var description: String {
        switch self {
        case .divisionByZero: return "Division by zero"
        case .negativeSquareRoot: return "Square root of negative number"
        case .negativeFactorial: return "Factorial of negative number"
        case .overflow: return "Result overflow"
        case .invalidLogarithm: return "Logarithm of non-positive number"
        }
    }
}
