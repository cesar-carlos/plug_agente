import 'package:fluent_ui/fluent_ui.dart';

class EmptyState extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  bool get hasError => _error != null;
  bool get hasErrorOrLoading => hasError || _isLoading;
}
