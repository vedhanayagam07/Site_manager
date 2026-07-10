// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'demo_session_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DemoSessionNotifier)
final demoSessionProvider = DemoSessionNotifierProvider._();

final class DemoSessionNotifierProvider
    extends $NotifierProvider<DemoSessionNotifier, DemoUser?> {
  DemoSessionNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'demoSessionProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$demoSessionNotifierHash();

  @$internal
  @override
  DemoSessionNotifier create() => DemoSessionNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DemoUser? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DemoUser?>(value),
    );
  }
}

String _$demoSessionNotifierHash() =>
    r'fe1e3e6a14560211aa609a3e6fa144c386f3278b';

abstract class _$DemoSessionNotifier extends $Notifier<DemoUser?> {
  DemoUser? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DemoUser?, DemoUser?>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<DemoUser?, DemoUser?>, DemoUser?, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}
