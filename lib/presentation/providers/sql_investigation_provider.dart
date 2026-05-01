import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/domain/entities/sql_investigation_event.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';

/// Presentation bridge for the in-memory SQL investigation feed.
class SqlInvestigationProvider extends ChangeNotifier {
  SqlInvestigationProvider(
    this._collector, {
    Duration debounceDelay = const Duration(milliseconds: 80),
  }) : _debounceDelay = debounceDelay {
    _subscription = _collector.eventsStream.listen((_) => _scheduleNotify());
    _revisionSubscription = _collector.feedRevisionStream.listen((_) => _scheduleNotify());
  }

  final ISqlInvestigationCollector _collector;
  final Duration _debounceDelay;
  StreamSubscription<SqlInvestigationEvent>? _subscription;
  StreamSubscription<void>? _revisionSubscription;
  Timer? _notifyDebounceTimer;

  List<SqlInvestigationEvent> get events => _collector.events;

  void _scheduleNotify() {
    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = Timer(_debounceDelay, () {
      _notifyDebounceTimer = null;
      notifyListeners();
    });
  }

  void clearEvents() {
    _collector.clear();
  }

  @override
  void dispose() {
    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _revisionSubscription?.cancel();
    _revisionSubscription = null;
    super.dispose();
  }
}
