import Foundation

/// Shared scan-limit constants for full-library fetches that fall back to
/// Swift-level evaluation (documented 2000-item ceiling in ARCHITECTURE.md).
/// Each cap is named for its business consequence — they intentionally share
/// a value today but may diverge.
enum LibraryScanLimits {
    /// Filter/sort refinement: max candidates materialized when Swift-level
    /// refinement (search, network/genre/year/provider filters, smart rules) is needed.
    static let refinementCandidateCap = 2000
    /// Batch size for the batched refinement candidate scan.
    static let refinementBatchSize = 500
    /// Calendar view: max items scanned when the indexed-facet path is unavailable.
    static let calendarScanCap = 2000
    /// Stats surfaces (year in review, scoped stats): max items aggregated.
    static let statsScanCap = 2000
    /// Smart-collection counting: max items fetched for Swift-level rule evaluation.
    static let smartCollectionCountCap = 2000
    /// Metadata-only scans (distinct years, release-date windows): max items fetched.
    static let metadataScanCap = 2000
}
