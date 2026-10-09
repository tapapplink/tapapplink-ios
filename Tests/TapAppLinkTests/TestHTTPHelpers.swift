import Foundation

enum TestHTTPHelpers {
  static func requestJSON(_ request: URLRequest?) -> [String: Any]? {
    guard let data = request?.httpBody else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
}
