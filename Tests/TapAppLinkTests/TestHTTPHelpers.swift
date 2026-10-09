import Foundation

enum TestHTTPHelpers {
  static func requestJSON(_ request: URLRequest?) -> [String: Any]? {
    guard let request else { return nil }
    guard let data = bodyData(from: request) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  /// `URLSession` may expose the body only via `httpBodyStream` inside `URLProtocol`.
  static func bodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
      return body
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
      let read = stream.read(buffer, maxLength: bufferSize)
      if read < 0 {
        return nil
      }
      if read == 0 {
        break
      }
      data.append(buffer, count: read)
    }
    return data.isEmpty ? nil : data
  }
}
