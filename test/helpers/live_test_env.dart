import 'e2e_env.dart';

/// Loads project `.env` and platform env for live / E2E tests.
///
/// Prefer calling this at the start of each `test/live/*` `main` instead of
/// duplicating `E2EEnv.load()` intent.
Future<void> loadLiveTestEnv() => E2EEnv.load();
