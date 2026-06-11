import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Reads an optional dependency exposed through [Provider] without touching getIt.
T? readOptionalPresentationProvider<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
