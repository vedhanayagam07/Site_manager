// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'worker_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workerService)
final workerServiceProvider = WorkerServiceProvider._();

final class WorkerServiceProvider
    extends $FunctionalProvider<WorkerService, WorkerService, WorkerService>
    with $Provider<WorkerService> {
  WorkerServiceProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'workerServiceProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$workerServiceHash();

  @$internal
  @override
  $ProviderElement<WorkerService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  WorkerService create(Ref ref) {
    return workerService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkerService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkerService>(value),
    );
  }
}

String _$workerServiceHash() => r'dec2eac91155fb595df86c3f5de925ba51f49927';

@ProviderFor(allWorkers)
final allWorkersProvider = AllWorkersProvider._();

final class AllWorkersProvider extends $FunctionalProvider<
        AsyncValue<List<Worker>>, List<Worker>, FutureOr<List<Worker>>>
    with $FutureModifier<List<Worker>>, $FutureProvider<List<Worker>> {
  AllWorkersProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'allWorkersProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$allWorkersHash();

  @$internal
  @override
  $FutureProviderElement<List<Worker>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Worker>> create(Ref ref) {
    return allWorkers(ref);
  }
}

String _$allWorkersHash() => r'1b9c64e5f6402efe12ed4220ad8954204c77a21e';

@ProviderFor(workersBySite)
final workersBySiteProvider = WorkersBySiteFamily._();

final class WorkersBySiteProvider extends $FunctionalProvider<
        AsyncValue<List<Worker>>, List<Worker>, FutureOr<List<Worker>>>
    with $FutureModifier<List<Worker>>, $FutureProvider<List<Worker>> {
  WorkersBySiteProvider._(
      {required WorkersBySiteFamily super.from, required String super.argument})
      : super(
          retry: null,
          name: r'workersBySiteProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$workersBySiteHash();

  @override
  String toString() {
    return r'workersBySiteProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Worker>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Worker>> create(Ref ref) {
    final argument = this.argument as String;
    return workersBySite(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkersBySiteProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workersBySiteHash() => r'd7029deda1cc4abe334e3479c91b02250910df12';

final class WorkersBySiteFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Worker>>, String> {
  WorkersBySiteFamily._()
      : super(
          retry: null,
          name: r'workersBySiteProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  WorkersBySiteProvider call(
    String siteId,
  ) =>
      WorkersBySiteProvider._(argument: siteId, from: this);

  @override
  String toString() => r'workersBySiteProvider';
}

@ProviderFor(workerById)
final workerByIdProvider = WorkerByIdFamily._();

final class WorkerByIdProvider
    extends $FunctionalProvider<AsyncValue<Worker>, Worker, FutureOr<Worker>>
    with $FutureModifier<Worker>, $FutureProvider<Worker> {
  WorkerByIdProvider._(
      {required WorkerByIdFamily super.from, required String super.argument})
      : super(
          retry: null,
          name: r'workerByIdProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$workerByIdHash();

  @override
  String toString() {
    return r'workerByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Worker> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Worker> create(Ref ref) {
    final argument = this.argument as String;
    return workerById(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkerByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workerByIdHash() => r'e333ab916ef09d597f2cf33fc010bfffc8cbdd2f';

final class WorkerByIdFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Worker>, String> {
  WorkerByIdFamily._()
      : super(
          retry: null,
          name: r'workerByIdProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  WorkerByIdProvider call(
    String workerId,
  ) =>
      WorkerByIdProvider._(argument: workerId, from: this);

  @override
  String toString() => r'workerByIdProvider';
}
