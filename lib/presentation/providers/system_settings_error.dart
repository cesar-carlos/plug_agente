import 'package:flutter/foundation.dart';

/// Tipo de erro emitido pelo `SystemSettingsProvider`. Cada caso mapeia para
/// uma chave ARB na camada de apresentação, mantendo o provider livre de
/// strings localizadas.
enum SystemSettingsErrorCode {
  /// Falha ao habilitar/desabilitar inicialização automática (ex.: registry,
  /// permissão negada). Acompanhado do detalhe técnico vindo do adapter de SO
  /// quando disponível.
  startupToggleFailed,

  /// O serviço de inicialização automática não foi registrado para o ambiente
  /// atual (ex.: build não-desktop ou compilação sem suporte a auto-start).
  startupServiceUnavailable,

  /// Falha ao abrir o painel de configurações do sistema operacional.
  startupOpenSystemSettingsFailed,
}

/// Estado de erro estruturado exposto pelo `SystemSettingsProvider`.
///
/// `code` identifica o caso para tradução via ARB. `detail` carrega a mensagem
/// crua vinda do adapter (geralmente já em PT/EN dependendo do SO) e deve ser
/// usada apenas como informação adicional, nunca como texto principal.
@immutable
class SystemSettingsErrorState {
  const SystemSettingsErrorState({
    required this.code,
    this.detail,
  });

  final SystemSettingsErrorCode code;
  final String? detail;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SystemSettingsErrorState && other.code == code && other.detail == detail;
  }

  @override
  int get hashCode => Object.hash(code, detail);

  @override
  String toString() => 'SystemSettingsErrorState(code: $code, detail: $detail)';
}
