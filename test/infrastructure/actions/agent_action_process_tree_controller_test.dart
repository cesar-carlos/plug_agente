import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_tree_controller.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_job_api.dart';
import 'package:win32/win32.dart';

void main() {
  for (final terminationOk in [true, false]) {
    test('termination after release preserves result without touching a reusable handle ($terminationOk)', () async {
      final api = _FakeApi();
      final controller = WindowsJobObjectProcessTreeController(api: api);
      final lease = (await controller.attach(_Process())).getOrThrow();
      api.terminateOk = terminationOk;
      final released = await controller.release(lease);
      final calls = List<String>.of(api.calls);
      // A closed numeric handle may now identify an unrelated Windows job.
      api.terminateOk = !terminationOk;
      final terminated = await controller.terminate(lease);
      expect(api.calls, calls);
      expect(terminated, same(released));
    });
  }
  test('applies CPU cap before assignment and reads job accounting', () async {
    final api = _FakeApi();
    final controller = WindowsJobObjectProcessTreeController(api: api, cpuLimitPercent: 50);
    final lease = (await controller.attach(_Process())).getOrThrow();
    expect(api.calls.indexOf('cpu:50'), lessThan(api.calls.indexOf('assign')));
    expect(controller.readCpu(lease).getOrThrow(), const Duration(seconds: 2));
    await controller.release(lease);
    expect(controller.readCpu(lease).isError(), isTrue);
  });
  test('CPU policy failure closes the job and refuses to start unprotected', () async {
    final api = _FakeApi()..cpuOk = false;
    final result = await WindowsJobObjectProcessTreeController(api: api, cpuLimitPercent: 25).attach(_Process());
    expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
    expect(api.calls, ['create', 'configure', 'cpu:25', 'close:1']);
  });
  test('invalid CPU policy fails before allocating a job', () async {
    final api = _FakeApi();
    final result = await WindowsJobObjectProcessTreeController(api: api, cpuLimitPercent: 101).attach(_Process());
    expect(result.isError(), isTrue);
    expect(api.calls, isEmpty);
  });
  test('Windows stores the requested CPU hard cap', () {
    final api = WindowsActionJobApi();
    final job = api.create().value;
    final limits = calloc<ActionJobCpuLimits>();
    try {
      expect(api.configureCpu(job, 50).value, isTrue);
      expect(
        QueryInformationJobObject(
          job,
          JobObjectCpuRateControlInformation,
          limits,
          sizeOf<ActionJobCpuLimits>(),
          null,
        ).value,
        isTrue,
      );
      expect(limits.ref.flags, 5);
      expect(limits.ref.rate, 5000);
    } finally {
      calloc.free(limits);
      api.close(job);
    }
  }, skip: !Platform.isWindows);

  test('configures a finite tree memory limit before attaching the process', () async {
    final api = _FakeApi();
    final controller = WindowsJobObjectProcessTreeController(api: api);
    final attached = await controller.attach(_Process());
    expect(attached.isSuccess(), isTrue);
    expect(api.memory, 2 * 1024 * 1024 * 1024);
    expect(api.calls, ['create', 'configure', 'open', 'assign', 'close:2']);
    expect((await controller.release(attached.getOrThrow())).isSuccess(), isTrue);
  });

  test('refuses an unprotected process when memory configuration fails', () async {
    final api = _FakeApi()..configureOk = false;
    final result = await WindowsJobObjectProcessTreeController(api: api).attach(_Process());
    expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
    expect(api.calls, ['create', 'configure', 'close:1']);
  });

  test('reports termination failure even when close succeeds and is idempotent', () async {
    final api = _FakeApi();
    final controller = WindowsJobObjectProcessTreeController(api: api);
    final lease = (await controller.attach(_Process())).getOrThrow();
    api.terminateOk = false;
    final result = await controller.release(lease);
    expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
    expect((result.exceptionOrNull()! as ActionRuntimeFailure).context['reason'], 'process_tree_cleanup_failed');
    expect(api.calls.last, 'close:1');
    final count = api.calls.length;
    expect((await controller.release(lease)).isError(), isTrue);
    expect(api.calls.length, count);
  });

  test('reports a failed close and allows another cleanup attempt', () async {
    final api = _FakeApi();
    final controller = WindowsJobObjectProcessTreeController(api: api);
    final lease = (await controller.attach(_Process())).getOrThrow();
    api.closeOk = false;
    expect((await controller.release(lease)).isError(), isTrue);
    api.closeOk = true;
    expect((await controller.release(lease)).isSuccess(), isTrue);
  });

  test('Windows stores the memory ceiling and kill-on-close flags', () {
    final api = WindowsActionJobApi();
    final job = api.create().value;
    expect(job.isNull, isFalse);
    final info = calloc<ActionJobExtendedLimits>();
    try {
      expect(api.configure(job, 128 * 1024 * 1024).value, isTrue);
      expect(
        QueryInformationJobObject(
          job,
          JobObjectExtendedLimitInformation,
          info,
          sizeOf<ActionJobExtendedLimits>(),
          nullptr,
        ).value,
        isTrue,
      );
      expect(info.ref.jobMemory, 128 * 1024 * 1024);
      expect(info.ref.basic.flags & WindowsActionJobApi.jobMemoryLimit, isNonZero);
      expect(info.ref.basic.flags & WindowsActionJobApi.killOnJobClose, isNonZero);
    } finally {
      calloc.free(info);
      expect(api.close(job).value, isTrue);
    }
  }, skip: !Platform.isWindows);
}

class _Process implements Process {
  @override
  int get pid => 123;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeApi extends WindowsActionJobApi {
  final calls = <String>[];
  bool cpuOk = true;
  @override
  Win32Result<bool> configureCpu(HANDLE job, int percent) {
    calls.add('cpu:$percent');
    return _result(cpuOk);
  }

  @override
  Win32Result<int> cpuTicks(HANDLE job) => const Win32Result(value: 20000000, error: ERROR_SUCCESS);
  int? memory;
  bool configureOk = true;
  bool terminateOk = true;
  bool closeOk = true;
  Win32Result<bool> _result(bool ok) => Win32Result(value: ok, error: ok ? ERROR_SUCCESS : ERROR_ACCESS_DENIED);
  @override
  Win32Result<HANDLE> create() {
    calls.add('create');
    return Win32Result(value: HANDLE(Pointer.fromAddress(1)), error: ERROR_SUCCESS);
  }

  @override
  Win32Result<bool> configure(HANDLE job, int memoryLimitBytes) {
    calls.add('configure');
    memory = memoryLimitBytes;
    return _result(configureOk);
  }

  @override
  Win32Result<HANDLE> open(int pid) {
    calls.add('open');
    return Win32Result(value: HANDLE(Pointer.fromAddress(2)), error: ERROR_SUCCESS);
  }

  @override
  Win32Result<bool> assign(HANDLE job, HANDLE process) {
    calls.add('assign');
    return _result(true);
  }

  @override
  Win32Result<bool> terminate(HANDLE job, int exitCode) {
    calls.add('terminate');
    return _result(terminateOk);
  }

  @override
  Win32Result<bool> close(HANDLE handle) {
    calls.add('close:${handle.address}');
    return _result(closeOk);
  }
}
