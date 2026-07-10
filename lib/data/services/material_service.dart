import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/material.dart';

class MaterialService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _tableName = 'materials';

  Future<List<Material>> getAllMaterials() async {
    try {
      final response = await _supabase.from(_tableName).select();
      return (response as List).map((e) => Material.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch materials: $e');
    }
  }

  Future<List<Material>> getMaterialsBySite(String siteId) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .select()
          .eq('site_id', siteId);
      return (response as List).map((e) => Material.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch materials for site: $e');
    }
  }

  Future<Material> getMaterialById(String id) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .select()
          .eq('id', id)
          .single();
      return Material.fromJson(response);
    } catch (e) {
      throw Exception('Failed to fetch material: $e');
    }
  }

  Future<Material> createMaterial(Material material) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .insert(material.toJson())
          .select()
          .single();
      return Material.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create material: $e');
    }
  }

  Future<Material> updateMaterial(String id, Material material) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .update(material.toJson())
          .eq('id', id)
          .select()
          .single();
      return Material.fromJson(response);
    } catch (e) {
      throw Exception('Failed to update material: $e');
    }
  }

  Future<void> deleteMaterial(String id) async {
    try {
      await _supabase.from(_tableName).delete().eq('id', id);
    } catch (e) {
      throw Exception('Failed to delete material: $e');
    }
  }
}
