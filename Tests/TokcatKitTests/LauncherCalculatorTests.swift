import XCTest
@testable import TokcatKit

final class LauncherCalculatorTests: XCTestCase {
    private func assertValue(_ expression: String, _ expected: Double,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard case .result(let value, _) = LauncherCalculator.evaluate(expression) else {
            XCTFail("Expected a result for \(expression)", file: file, line: line)
            return
        }
        XCTAssertEqual(value, expected, accuracy: max(abs(expected) * 1e-14, 1e-15), expression, file: file, line: line)
    }

    func testArithmeticPrecedencePowerUnaryAndPercentages() {
        for (expression, result) in ["2+3*4": 14.0, "(2+3)*4": 20, "-2^2": -4,
            "(-2)^2": 4, "2^3^2": 512, "2^-2": 0.25, "2**3": 8,
            "200*10%": 20, ".5*.2": 0.1, "1e-3*2000": 2,
            "（２＋３）×４÷２": 10, "−2+3": 1] {
            assertValue(expression, result)
        }
    }

    func testNestedFunctionsConstantsAndArguments() {
        for (expression, result) in ["sqrt(9)": 3.0, "SQRT(abs(-81))+pow(2,3)": 17,
            "sin(pi/2)": 1, "cos(0)": 1, "tan(0)": 0, "π*2": Double.pi * 2,
            "ln(e)": 1, "log(100)": 2, "log10(1000)": 3, "log2(8)": 3,
            "round(2.6)": 3, "floor(2.9)": 2, "ceil(2.1)": 3,
            "max(2,min(3,4),-1)": 3, "=e": exp(Double(1))] {
            assertValue(expression, result)
        }
    }

    func testFormattingAvoidsFloatingPointNoiseAndKeepsSmallValues() {
        XCTAssertEqual(LauncherCalculator.evaluate("0.1+0.2")?.formattedResult, "0.3")
        XCTAssertEqual(LauncherCalculator.evaluate("-0")?.formattedResult, "0")
        XCTAssertEqual(LauncherCalculator.evaluate("1e-20")?.formattedResult, "1e-20")
        XCTAssertEqual(LauncherCalculator.evaluate("sqrt(16)")?.formattedResult, "4")
    }

    func testIncompleteAndInvalidExpressions() {
        for expression in ["1+", "sqrt(", "(2+3", "1e-", "="] {
            XCTAssertEqual(LauncherCalculator.evaluate(expression), .incomplete, expression)
        }
        for expression in ["1/0", "sqrt(-1)", "ln(0)", "pow(-1,0.5)", "pow(2)",
            "sqrt()", "sqrt(1,2)", "min()", "1..2", "2^^3", "min(1,)", "2 3", "1e999", "exp(1000)"] {
            guard case .error = LauncherCalculator.evaluate(expression) else {
                XCTFail("Expected an error for \(expression)"); continue
            }
        }
        XCTAssertEqual(LauncherCalculator.evaluate("1/0"), .error("不能除以 0"))
        XCTAssertEqual(LauncherCalculator.evaluate("sqrt(-1)"), .error("平方根的参数不能是负数"))
    }

    func testDoesNotInterceptApplicationNamesOrTerminalCommands() {
        for query in ["", "Chrome", "1Password", "1ePassword", "Visual Studio Code", "sqrt", "max", "e",
                      "> sqrt(9)", "sqrt(9); tell application Terminal", "__import__('os')"] {
            XCTAssertNil(LauncherCalculator.evaluate(query), query)
        }
    }

    func testLongAndDeepExpressionsAreBounded() {
        XCTAssertEqual(LauncherCalculator.evaluate(String(repeating: "(", count: 70) + "1" + String(repeating: ")", count: 70)),
                       .error("算式嵌套过深"))
        XCTAssertEqual(LauncherCalculator.evaluate(String(repeating: "1+", count: 600)),
                       .error("算式过长，请缩短后再试"))
    }

    func testCalculationHistoryRoundTripPreservesExistingCommands() {
        var history = LauncherHistory()
        history.record(text: "> pwd")
        history.record(text: "sqrt(9)")
        history.record(text: "1/0")
        history.record(text: "1+")
        XCTAssertEqual(history.entries.map(\.text), ["sqrt(9)", "> pwd"])
        let restored = LauncherHistory(entries: history.entries)
        XCTAssertEqual(restored, history)
    }
}
