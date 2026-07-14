import Foundation

enum JSONDict {
    static func dictionary(_ any: Any?) -> [String: Any]? {
        if let dict = any as? [String: Any] {
            return dict
        }
        if let dict = any as? NSDictionary {
            var result: [String: Any] = [:]
            result.reserveCapacity(dict.count)
            for (key, value) in dict {
                if let key = key as? String {
                    result[key] = value
                }
            }
            return result
        }
        return nil
    }

    static func string(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let s = any as? NSString { return s as String }
        return nil
    }

    static func int(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let i = Int(s) { return i }
        return 0
    }
}
