import Foundation

/// Swift Testing's `@Suite struct` can't be passed to `Bundle(for:)`, so fixture lookups need a class.
/// The non-empty body is deliberate: a bare `final class {}` stub trips Sonar S2094.
final class TestBundleAnchor {
    static let bundle = Bundle(for: TestBundleAnchor.self)
}
