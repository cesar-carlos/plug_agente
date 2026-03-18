import 'package:flutter/widgets.dart';
import 'package:plug_agente/infrastructure/runtime/windows_runtime_probe.dart';
import 'package:plug_agente/presentation/boot/app_initializer.dart';
import 'package:plug_agente/presentation/boot/app_root.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final initializer = AppInitializer(runtimeProbe: WindowsRuntimeProbe());
  final bootstrapData = await initializer.initialize(args);
  runApp(
    AppRoot(
      initialRoute: bootstrapData.initialRoute,
      capabilities: bootstrapData.capabilities,
    ),
  );
}
