import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/site.dart';

class SiteService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _tableName = 'sites';

  Future<List<Site>> getAllSites() async {
    try {
      final response = await _supabase.from(_tableName).select();
      return (response as List).map((e) => Site.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch sites: $e');
    }
  }

  Future<Site> getSiteById(String id) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .select()
          .eq('id', id)
          .single();
      return Site.fromJson(response);
    } catch (e) {
      throw Exception('Failed to fetch site: $e');
    }
  }

  Future<Site> createSite(Site site) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .insert(site.toJson())
          .select()
          .single();
      return Site.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create site: $e');
    }
  }

  Future<Site> updateSite(String id, Site site) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .update(site.toJson())
          .eq('id', id)
          .select()
          .single();
      return Site.fromJson(response);
    } catch (e) {
      throw Exception('Failed to update site: $e');
    }
  }

  Future<void> deleteSite(String id) async {
    try {
      await _supabase.from(_tableName).delete().eq('id', id);
    } catch (e) {
      throw Exception('Failed to delete site: $e');
    }
  }
}
