// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'material_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(materialService)
final materialServiceProvider = MaterialServiceProvider._();

final class MaterialServiceProvider extends $FunctionalProvider<MaterialService,
    MaterialService, MaterialService> with $Provider<MaterialService> {
  MaterialServiceProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'materialServiceProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$materialServiceHash();

  @$internal
  @override
  $ProviderElement<MaterialService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MaterialService create(Ref ref) {
    return materialService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MaterialService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MaterialService>(value),
    );
  }
}

String _$materialServiceHash() => r'e5ab392d57668e52ec6055cb224ef3118f95e0e9';

@ProviderFor(allMaterials)
final allMaterialsProvider = AllMaterialsProvider._();

final class AllMaterialsProvider extends $FunctionalProvider<
        AsyncValue<List<Material>>, List<Material>, FutureOr<List<Material>>>
    with $FutureModifier<List<Material>>, $FutureProvider<List<Material>> {
  AllMaterialsProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'allMaterialsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$allMaterialsHash();

  @$internal
  @override
  $FutureProviderElement<List<Material>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Material>> create(Ref ref) {
    return allMaterials(ref);
  }
}

String _$allMaterialsHash() => r'f91ec30a799d92c5c521696d743ed919deb38a22';

@ProviderFor(materialsBySite)
final materialsBySiteProvider = MaterialsBySiteFamily._();

final class MaterialsBySiteProvider extends $FunctionalProvider<
        AsyncValue<List<Material>>, List<Material>, FutureOr<List<Material>>>
    with $FutureModifier<List<Material>>, $FutureProvider<List<Material>> {
  MaterialsBySiteProvider._(
      {required MaterialsBySiteFamily super.from,
      required String super.argument})
      : super(
          retry: null,
          name: r'materialsBySiteProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$materialsBySiteHash();

  @override
  String toString() {
    return r'materialsBySiteProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Material>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Material>> create(Ref ref) {
    final argument = this.argument as String;
    return materialsBySite(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MaterialsBySiteProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$materialsBySiteHash() => r'4ae60b5ef428f324048c9e377a1e2dde26f62b05';

final class MaterialsBySiteFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Material>>, String> {
  MaterialsBySiteFamily._()
      : super(
          retry: null,
          name: r'materialsBySiteProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  MaterialsBySiteProvider call(
    String siteId,
  ) =>
      MaterialsBySiteProvider._(argument: siteId, from: this);

  @override
  String toString() => r'materialsBySiteProvider';
}

@ProviderFor(materialById)
final materialByIdProvider = MaterialByIdFamily._();

final class MaterialByIdProvider extends $FunctionalProvider<
        AsyncValue<Material>, Material, FutureOr<Material>>
    with $FutureModifier<Material>, $FutureProvider<Material> {
  MaterialByIdProvider._(
      {required MaterialByIdFamily super.from, required String super.argument})
      : super(
          retry: null,
          name: r'materialByIdProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$materialByIdHash();

  @override
  String toString() {
    return r'materialByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Material> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Material> create(Ref ref) {
    final argument = this.argument as String;
    return materialById(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MaterialByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$materialByIdHash() => r'97a6d32ea399cf8d5fb54f8c648e2cbe4a44e7e5';

final class MaterialByIdFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Material>, String> {
  MaterialByIdFamily._()
      : super(
          retry: null,
          name: r'materialByIdProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  MaterialByIdProvider call(
    String materialId,
  ) =>
      MaterialByIdProvider._(argument: materialId, from: this);

  @override
  String toString() => r'materialByIdProvider';
}
