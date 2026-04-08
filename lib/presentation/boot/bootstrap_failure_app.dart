import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';

class BootstrapFailureApp extends StatelessWidget {
  const BootstrapFailureApp({
    required this.error,
    this.stackTrace,
    super.key,
  });

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('pt'),
      home: _BootstrapFailurePage(
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }
}

class _BootstrapFailurePage extends StatefulWidget {
  const _BootstrapFailurePage({
    required this.error,
    this.stackTrace,
  });

  final Object error;
  final StackTrace? stackTrace;

  @override
  State<_BootstrapFailurePage> createState() => _BootstrapFailurePageState();
}

class _BootstrapFailurePageState extends State<_BootstrapFailurePage> {
  bool _closeRequested = false;
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showStartupErrorDialog();
    });
  }

  Future<void> _showStartupErrorDialog() async {
    if (_dialogShown || !mounted) {
      return;
    }
    _dialogShown = true;

    final userMessage = BootstrapFailureMessageBuilder.userMessage(
      widget.error,
    );
    final details = BootstrapFailureMessageBuilder.technicalDetails(
      error: widget.error,
      stackTrace: widget.stackTrace,
    );

    await MessageModal.show<void>(
      context: context,
      title: AppStrings.bootstrapFailureTitle,
      message: userMessage,
      type: MessageType.error,
      confirmText: AppStrings.bootstrapFailureButtonClose,
      onConfirm: _requestClose,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 12),
          const Text(AppStrings.bootstrapFailureTechnicalDetails),
          const SizedBox(height: 8),
          SizedBox(
            width: 720,
            child: SelectableText(details),
          ),
        ],
      ),
    );

    if (!_closeRequested) {
      _requestClose();
    }
  }

  void _requestClose() {
    if (_closeRequested) {
      return;
    }
    _closeRequested = true;
    Future<void>.microtask(_closeApplication);
  }

  Future<void> _closeApplication() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      exit(1);
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return const NavigationView(
      content: SizedBox.expand(),
    );
  }
}

class BootstrapFailureMessageBuilder {
  BootstrapFailureMessageBuilder._();

  static String userMessage(Object error) {
    if (error is GlobalStorageBootstrapException) {
      return AppStrings.bootstrapFailureStorageMessage;
    }

    return AppStrings.bootstrapFailureGenericMessage;
  }

  static String technicalDetails({
    required Object error,
    StackTrace? stackTrace,
  }) {
    if (error is GlobalStorageBootstrapException) {
      final attempts = error.attempts.isEmpty
          ? ' - nenhuma tentativa registrada'
          : error.attempts.map((attempt) => ' - $attempt').join('\n');
      final stack = stackTrace?.toString().trim();
      if (stack == null || stack.isEmpty) {
        return 'Codigo: ${GlobalStorageBootstrapException.code}\n'
            'Mensagem: ${error.message}\n'
            'Tentativas:\n$attempts';
      }

      return 'Codigo: ${GlobalStorageBootstrapException.code}\n'
          'Mensagem: ${error.message}\n'
          'Tentativas:\n$attempts\n\n'
          '$stack';
    }

    final stack = stackTrace?.toString().trim();
    if (stack == null || stack.isEmpty) {
      return error.toString();
    }
    return '$error\n\n$stack';
  }
}
