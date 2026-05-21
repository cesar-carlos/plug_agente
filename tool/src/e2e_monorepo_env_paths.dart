/// Candidate `.env` paths for sibling Hub repos in a monorepo layout.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Ordered Hub/server `.env` paths to try (existing files only).
List<String> siblingHubEnvFileCandidates(String projectRoot) {
  final parent = Directory(p.dirname(projectRoot)).path;
  final fromEnv = Platform.environment['PLUG_SERVER_ENV']?.trim();
  final candidates = <String>[
    if (fromEnv != null && fromEnv.isNotEmpty) fromEnv,
    p.join(parent, 'plug_server', '.env'),
    p.join(parent, 'plug_node', '.env'),
    p.join(parent, '..', 'plug_server', '.env'),
  ];
  final seen = <String>{};
  return candidates.where((path) => seen.add(p.normalize(path))).where((path) => File(path).existsSync()).toList();
}

/// Directory roots for sibling Hub repos (for creating `.env` when missing).
List<String> siblingHubProjectRoots(String projectRoot) {
  final parent = Directory(p.dirname(projectRoot)).path;
  final fromEnv = Platform.environment['PLUG_SERVER_ENV']?.trim();
  final candidates = <String>[
    if (fromEnv != null && fromEnv.isNotEmpty) p.dirname(fromEnv),
    p.join(parent, 'plug_server'),
    p.join(parent, 'plug_node'),
    p.join(parent, '..', 'plug_server'),
  ];
  final seen = <String>{};
  return candidates.where((path) => seen.add(p.normalize(path))).toList();
}
