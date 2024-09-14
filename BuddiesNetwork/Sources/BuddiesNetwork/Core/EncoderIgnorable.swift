import Foundation

/// This property wrapper can be used to ignore some properties to be ignored in `Requestable`
/// The main purpose of this is because sometimes the property in `Requestable` is desired to be on the `URL` but not as a `QueryItem`
/// For example:
///        desiredUrl = `dummyApi.com/v2/cities/nl?subway=true`
///        `Requestable` would be like
/// ```
/// struct CityRequest: Requestable {
///     @EncoderIgnorable var countryCode: String
///     var subway: Bool
///
///     func toUrlRequest() throws -> URLRequest {
///         try URLHelper.request(
///             base: "dummyApi.com/v2",
///             path: "cities/\(self.countryCode)", // Here you can see that countryCode is being used on the URL path but not as a queryItem.
///             data: self)
///     }
/// ```
@propertyWrapper
public struct EncoderIgnorable<T>: Encodable {
    public var wrappedValue: T?

    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }

    public func encode(to encoder: Encoder) throws {
        // Do nothing
    }
}

public extension KeyedEncodingContainer {
    mutating func encode(
        _ value: EncoderIgnorable<some Any>,
        forKey key: KeyedEncodingContainer<K>.Key
    ) throws {
        // Do nothing
    }
}
