// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'site_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(siteService)
final siteServiceProvider = SiteServiceProvider._();

final class SiteServiceProvider
    extends $FunctionalProvider<SiteService, SiteService, SiteService>
    with $Provider<SiteService> {
  SiteServiceProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'siteServiceProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$siteServiceHash();

  @$internal
  @override
  $ProviderElement<SiteService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SiteService create(Ref ref) {
    return siteService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SiteService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SiteService>(value),
    );
  }
}

String _$siteServiceHash() => r'c3a99f5495dd0cf66e3c1153ba2b0e2fc94de580';

@ProviderFor(allSites)
final allSitesProvider = AllSitesProvider._();

final class AllSitesProvider extends $FunctionalProvider<AsyncValue<List<Site>>,
        List<Site>, FutureOr<List<Site>>>
    with $FutureModifier<List<Site>>, $FutureProvider<List<Site>> {
  AllSitesProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'allSitesProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$allSitesHash();

  @$internal
  @override
  $FutureProviderElement<List<Site>> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Site>> create(Ref ref) {
    return allSites(ref);
  }
}

String _$allSitesHash() => r'65cab5cabe423f941a478af2c6cb2f4ad4a35512';

@ProviderFor(siteById)
final siteByIdProvider = SiteByIdFamily._();

final class SiteByIdProvider
    extends $FunctionalProvider<AsyncValue<Site>, Site, FutureOr<Site>>
    with $FutureModifier<Site>, $FutureProvider<Site> {
  SiteByIdProvider._(
      {required SiteByIdFamily super.from, required String super.argument})
      : super(
          retry: null,
          name: r'siteByIdProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$siteByIdHash();

  @override
  String toString() {
    return r'siteByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Site> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Site> create(Ref ref) {
    final argument = this.argument as String;
    return siteById(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SiteByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$siteByIdHash() => r'5786b9bd66c704f54fab613b24a6bdf875f79764';

final class SiteByIdFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Site>, String> {
  SiteByIdFamily._()
      : super(
          retry: null,
          name: r'siteByIdProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  SiteByIdProvider call(
    String siteId,
  ) =>
      SiteByIdProvider._(argument: siteId, from: this);

  @override
  String toString() => r'siteByIdProvider';
}
