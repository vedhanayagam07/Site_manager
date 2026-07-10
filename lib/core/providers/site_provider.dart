import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/site.dart';
import '../../data/services/site_service.dart';

part 'site_provider.g.dart';

@riverpod
SiteService siteService(Ref ref) => SiteService();

@riverpod
Future<List<Site>> allSites(Ref ref) async {
  final siteService = ref.watch(siteServiceProvider);
  return siteService.getAllSites();
}

@riverpod
Future<Site> siteById(Ref ref, String siteId) async {
  final siteService = ref.watch(siteServiceProvider);
  return siteService.getSiteById(siteId);
}
