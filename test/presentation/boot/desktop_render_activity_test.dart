import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/presentation/boot/desktop_render_activity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  late WindowManagerService window;
  var failHide = false;
  var preventClose = true;

  setUp(() {
    window = WindowManagerService();
    failHide = false;
    preventClose = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'hide' && failHide) throw PlatformException(code: 'hide_failed');
      if (call.method == 'isPreventClose') return preventClose;
      if (call.method == 'isMinimized') return false;
      return null;
    });
  });
  tearDown(() {
    window.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('tray stops frame scheduling without stopping background work or losing widget state', (tester) async {
    final key = GlobalKey<_ActivityProbeState>();
    await tester.pumpWidget(
      DesktopRenderActivity(
        activity: window,
        child: _ActivityProbe(key: key),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final state = key.currentState!;
    expect(tester.binding.hasScheduledFrame, isTrue);

    (await window.setCloseToTray(value: true)).getOrThrow();
    await window.onWindowClose();
    await tester.pump();
    final ticks = state.animationTicks;
    final work = state.backgroundTicks;
    await tester.pump(const Duration(seconds: 2));
    expect(state.animationTicks, ticks);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(state.backgroundTicks, greaterThan(work));

    await window.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(key.currentState, same(state));
    expect(state.animationTicks, greaterThan(ticks));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('minimize suspends animations, blur does not, and restore resumes', () {
    window.onWindowBlur();
    expect(window.renderingEnabled.value, isTrue);
    window.onWindowMinimize();
    expect(window.renderingEnabled.value, isFalse);
    window.onWindowRestore();
    expect(window.renderingEnabled.value, isTrue);
  });

  test('failed hide keeps visible UI animations enabled', () async {
    failHide = true;
    await expectLater(window.hide(), throwsA(isA<PlatformException>()));
    expect(window.renderingEnabled.value, isTrue);
  });

  test('close prevented by another operation keeps animations enabled', () async {
    await window.onWindowClose();
    expect(window.renderingEnabled.value, isTrue);
  });
}

class _ActivityProbe extends StatefulWidget {
  const _ActivityProbe({super.key});
  @override
  State<_ActivityProbe> createState() => _ActivityProbeState();
}

class _ActivityProbeState extends State<_ActivityProbe> with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Timer background;
  int animationTicks = 0;
  int backgroundTicks = 0;
  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(() => animationTicks++)
      ..repeat();
    background = Timer.periodic(const Duration(milliseconds: 100), (_) => backgroundTicks++);
  }

  @override
  void dispose() {
    controller.dispose();
    background.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
