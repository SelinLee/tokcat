import Foundation

public enum LauncherCalculation: Equatable, Sendable {
    case result(value: Double, formatted: String)
    case incomplete
    case error(String)

    public var formattedResult: String? {
        if case .result(_, let formatted) = self { return formatted }
        return nil
    }
}

/// A bounded arithmetic parser. Input is never evaluated as code or sent to a shell.
public enum LauncherCalculator {
    private static let functions: Set<String> = [
        "sqrt", "abs", "round", "floor", "ceil", "sin", "cos", "tan",
        "log", "log10", "log2", "ln", "exp", "pow", "min", "max"
    ]

    public static func evaluate(_ input: String) -> LauncherCalculation? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix(">") else { return nil }
        let explicit = text.hasPrefix("=")
        if explicit { text.removeFirst() }
        guard text.count <= 1_024 else {
            return explicit || text.first?.isNumber == true ? .error("算式过长，请缩短后再试") : nil
        }
        text = text.folding(options: [.widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "π", with: "pi")
        do {
            var lexer = Lexer(text: Array(text))
            let tokens = try lexer.tokenize()
            let containsOperand = tokens.enumerated().contains { index, token in
                switch token {
                case .number: return true
                case .name("pi"): return true
                case .name("e"): return explicit || tokens.count > 1
                case .name(let name): return functions.contains(name) && tokens.dropFirst(index + 1).first == .left
                default: return false
                }
            }
            guard explicit || containsOperand else { return nil }
            var parser = Parser(tokens: tokens)
            let value = try parser.parse()
            let formatted = String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value == 0 ? 0 : value).lowercased()
            return .result(value: value, formatted: formatted)
        } catch Failure.notMath {
            return explicit ? .error("不支持的函数、常量或字符") : nil
        } catch Failure.incomplete { return .incomplete }
        catch Failure.invalid(let message) { return .error(message) }
        catch { return .error("请检查算式") }
    }

    private enum Failure: Error {
        case notMath, incomplete, invalid(String)
    }

    private enum Token: Equatable {
        case number(Double), name(String)
        case plus, minus, multiply, divide, power, percent, left, right, comma
    }

    private struct Lexer {
        let text: [Character]
        var position = 0

        mutating func tokenize() throws -> [Token] {
            var tokens: [Token] = []
            while position < text.count {
                let character = text[position]
                if character.isWhitespace { position += 1; continue }
                if character.isASCIIDigit || character == "." {
                    tokens.append(.number(try number()))
                    continue
                }
                if character.isLetter {
                    let start = position
                    while position < text.count, text[position].isLetter || text[position].isASCIIDigit { position += 1 }
                    let name = String(text[start..<position]).lowercased()
                    guard functions.contains(name) || name == "pi" || name == "e" else { throw Failure.notMath }
                    tokens.append(.name(name))
                    continue
                }
                position += 1
                switch character {
                case "+": tokens.append(.plus)
                case "-": tokens.append(.minus)
                case "*":
                    if position < text.count, text[position] == "*" { position += 1; tokens.append(.power) }
                    else { tokens.append(.multiply) }
                case "/": tokens.append(.divide)
                case "^": tokens.append(.power)
                case "%": tokens.append(.percent)
                case "(": tokens.append(.left)
                case ")": tokens.append(.right)
                case ",": tokens.append(.comma)
                default: throw Failure.notMath
                }
            }
            return tokens
        }

        private mutating func number() throws -> Double {
            let start = position
            var digits = 0
            while position < text.count, text[position].isASCIIDigit { digits += 1; position += 1 }
            if position < text.count, text[position] == "." {
                position += 1
                while position < text.count, text[position].isASCIIDigit { digits += 1; position += 1 }
            }
            guard digits > 0 else { throw Failure.incomplete }
            if position < text.count, text[position] == "e" || text[position] == "E",
               position + 1 == text.count || text[position + 1].isASCIIDigit || text[position + 1] == "+" || text[position + 1] == "-" {
                position += 1
                if position < text.count, text[position] == "+" || text[position] == "-" { position += 1 }
                let exponentStart = position
                while position < text.count, text[position].isASCIIDigit { position += 1 }
                guard position > exponentStart else { throw Failure.incomplete }
            }
            guard let value = Double(String(text[start..<position])), value.isFinite else {
                throw Failure.invalid("数值超出可计算范围")
            }
            return value
        }
    }

    private struct Parser {
        let tokens: [Token]
        var position = 0
        var depth = 0
        var next: Token? { position < tokens.count ? tokens[position] : nil }

        mutating func parse() throws -> Double {
            let value = try sum()
            guard next == nil else { throw Failure.invalid("请检查括号和运算符") }
            return value
        }

        mutating func sum() throws -> Double {
            var value = try product()
            while let token = next, token == .plus || token == .minus {
                position += 1
                let right = try product()
                value = try checked(token == .plus ? value + right : value - right)
            }
            return value
        }

        mutating func product() throws -> Double {
            var value = try unary()
            while let token = next, token == .multiply || token == .divide {
                position += 1
                let right = try unary()
                if token == .divide, right == 0 { throw Failure.invalid("不能除以 0") }
                value = try checked(token == .multiply ? value * right : value / right)
            }
            return value
        }

        mutating func unary() throws -> Double {
            guard depth < 64 else { throw Failure.invalid("算式嵌套过深") }
            depth += 1
            defer { depth -= 1 }
            if next == .plus { position += 1; return try unary() }
            if next == .minus { position += 1; return try -unary() }
            return try power()
        }

        mutating func power() throws -> Double {
            var value = try primary()
            while next == .percent { position += 1; value /= 100 }
            if next == .power {
                position += 1
                // Unary on the right gives 2^-2, right associativity, and -2^2 = -4.
                let exponent = try unary()
                value = try checked(pow(value, exponent))
            }
            return value
        }

        mutating func primary() throws -> Double {
            guard let token = next else { throw Failure.incomplete }
            position += 1
            switch token {
            case .number(let value): return value
            case .left:
                let value = try sum()
                try closeParenthesis()
                return value
            case .name("pi"): return .pi
            case .name("e"): return exp(1)
            case .name(let name):
                guard next != nil else { throw Failure.incomplete }
                guard next == .left else { throw Failure.invalid("\(name) 后需要括号") }
                position += 1
                var arguments: [Double] = []
                if next != .right {
                    arguments.append(try sum())
                    while next == .comma { position += 1; arguments.append(try sum()) }
                }
                try closeParenthesis()
                return try function(name, arguments: arguments)
            default: throw Failure.invalid("这里需要一个数值")
            }
        }

        private mutating func closeParenthesis() throws {
            guard next != nil else { throw Failure.incomplete }
            guard next == .right else { throw Failure.invalid("请检查括号") }
            position += 1
        }

        private func function(_ name: String, arguments: [Double]) throws -> Double {
            if name == "min" || name == "max" {
                guard let value = name == "min" ? arguments.min() : arguments.max() else {
                    throw Failure.invalid("\(name)() 至少需要 1 个参数")
                }
                return value
            }
            if name == "pow" {
                guard arguments.count == 2 else { throw Failure.invalid("pow() 需要 2 个参数") }
                return try checked(pow(arguments[0], arguments[1]))
            }
            guard arguments.count == 1 else { throw Failure.invalid("\(name)() 需要 1 个参数") }
            let value = arguments[0]
            let result: Double
            switch name {
            case "sqrt":
                guard value >= 0 else { throw Failure.invalid("平方根的参数不能是负数") }
                result = sqrt(value)
            case "abs": result = abs(value)
            case "round": result = round(value)
            case "floor": result = floor(value)
            case "ceil": result = ceil(value)
            case "sin": result = sin(value)
            case "cos": result = cos(value)
            case "tan": result = tan(value)
            case "log", "log10", "log2", "ln":
                guard value > 0 else { throw Failure.invalid("对数的参数必须大于 0") }
                if name == "ln" { result = log(value) }
                else if name == "log2" { result = log2(value) }
                else { result = log10(value) }
            case "exp": result = exp(value)
            default: throw Failure.notMath
            }
            return try checked(result)
        }

        private func checked(_ value: Double) throws -> Double {
            guard !value.isNaN else { throw Failure.invalid("函数参数超出实数范围") }
            guard value.isFinite else { throw Failure.invalid("结果超出可计算范围") }
            return value
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
