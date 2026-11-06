# ODBC 5.0.2 review — 2026-11-06

`measurements.zip` preserves all 33 reviewed source, measurement and report
files, verified against their originals with SHA-256. Paths below refer to
entries in that archive. The final `controlled/quiet-summary.json` is also
available directly for review. Extract the archive before reproduction.

The final controlled comparison is in `controlled/quiet-summary.json`, with all
accepted measurements in `controlled/quiet2-raw.json`. It did not establish a
general performance improvement or a consistent regression. SQL Anywhere
columnar showed a favorable exploratory signal, with uncertainty about gains
above the predefined 5% practical threshold.

The final run used Windows AOT executables, verified release DLLs, a shared
8,000-row disposable fixture, identical CPU affinity and priority, five warm-up
batches, and eight paired rounds. Each measurement contained 15 timed batches of
48 queries. All 48 pairs passed the external-load filter. Mean external CPU was
5.73%. Database CPU was measured separately through Windows performance counters.
All result contents were validated and fixture cleanup completed successfully.
Confidence intervals are exploratory and unadjusted for multiple comparisons.
The host and databases remained shared. These are component measurements.

`controlled/quiet-raw.json` records the rejected initial load-filter attempt.
Its filter incorrectly counted local database CPU as external interference.
It must not be used to infer package performance. `controlled/raw.json` and
`controlled/summary.json` contain the earlier affinity-controlled experiment.
Root-level JSON files contain the original JIT/AOT comparisons.

`5.0.2/parameter-copy-aot.json` isolates removal of the parameter-map copy.
The measured preparation step improved by 59–67%, saving approximately
0.04–1.91 microseconds per invocation for 1–64 parameters. This is not an
end-to-end application throughput measurement.

Repository validation after the update completed with 828 tests passing and
three skipped, 11 native/runtime tests passing on SQL Server and SQL Anywhere,
and static analysis passing. Live verification covered reads, streaming and
pools. Writes and transactions were covered by isolated automated tests.

The Python and Dart files are snapshots of the executed benchmark harnesses.
They retain their original workspace-relative assumptions. To reproduce on a
configured Windows test host, restore this archive under
`build/odbc-version-benchmark`, resolve both exact package versions, and prepare
the checksummed native releases under `build/odbc-native/packages`. The runners
read test connection settings from the local `.env`, create disposable tables,
and remove them on completion. Native binaries, caches and credentials are
excluded from this archive. Re-running scripts overwrites their measurement
files, so preserve a separate copy when comparing new results.
