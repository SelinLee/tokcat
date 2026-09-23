import Foundation
import Vision

// OCR guard for documentation screenshots. Also review images visually for layout.
var failed = false
for path in CommandLine.arguments.dropFirst() {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US", "zh-Hans"]
    request.usesLanguageCorrection = false
    do {
        try VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let chinese = lines.filter { $0.range(of: "\\p{Han}", options: .regularExpression) != nil }
        if !chinese.isEmpty || lines.isEmpty {
            failed = true
            print("FAIL \(path): \(chinese.isEmpty ? "no text detected" : chinese.joined(separator: " | "))")
        } else {
            print("PASS \(URL(fileURLWithPath: path).lastPathComponent): \(lines.count) text lines, no Chinese text detected")
        }
    } catch {
        failed = true
        print("FAIL \(path): \(error)")
    }
}
exit(failed ? 1 : 0)
