import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/material.dart';
import '../../data/services/material_service.dart';

part 'material_provider.g.dart';

@riverpod
MaterialService materialService(Ref ref) => MaterialService();

@riverpod
Future<List<Material>> allMaterials(Ref ref) async {
  final materialService = ref.watch(materialServiceProvider);
  return materialService.getAllMaterials();
}

@riverpod
Future<List<Material>> materialsBySite(Ref ref, String siteId) async {
  final materialService = ref.watch(materialServiceProvider);
  return materialService.getMaterialsBySite(siteId);
}

@riverpod
Future<Material> materialById(Ref ref, String materialId) async {
  final materialService = ref.watch(materialServiceProvider);
  return materialService.getMaterialById(materialId);
}
