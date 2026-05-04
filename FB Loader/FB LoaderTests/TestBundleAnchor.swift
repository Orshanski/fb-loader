import Foundation

/// Single anchor class for `Bundle(for: AnyClass)` lookup of test resources
/// (`.fb2`, `.inpx` fixtures from `Fixtures/`). Swift Testing's `@Suite struct`
/// can't be passed to `Bundle(for:)`, so resource-loading tests need *some*
/// class type to identify their bundle.
///
/// Centralising into one helper avoids 1-line `private final class FooAnchor {}`
/// stubs scattered across test files (each of which Sonar flags as S2094 empty
/// class). The static `bundle` property gives the anchor a non-empty body —
/// satisfies S2094 — and exposes the bundle directly so call sites read
/// `TestBundleAnchor.bundle.url(...)` instead of `Bundle(for: ...Anchor.self)`.
final class TestBundleAnchor {
    static let bundle = Bundle(for: TestBundleAnchor.self)
}
