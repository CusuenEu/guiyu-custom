Self-tests use isolated temporary files only; they never rename or move real project data.
Coverage: local extraction/OCR; classification; download gating; virtual folder/year metadata;
native table selection/preview reload gate; naming rule priority, month prefix, filename title,
confirmed physical folder/file rename, collision protection and path mapping.

Search fixtures: `FilenameSearchTests.swift` checks GRDB use, one/two-character Chinese, Unicode/case/width normalization, multi-term AND, exact ranking, literal SQL input, no body persistence, directory/root scope, rename/delete/reopen/cache corruption, non-destructive fallback and latest-request publication. It reports synthetic 100-project/10,000-name initial-index, warm narrow and broad-query timings; these are backend timings, not UI latency.
`--ui-review` additionally renders multi-term and no-result searches, asserting native table row counts [1,6] and [0], plus the existing layout and interaction fixtures.
