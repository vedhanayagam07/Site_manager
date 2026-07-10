import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/worker.dart';

class WorkerService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _tableName = 'workers';

  Future<List<Worker>> getAllWorkers() async {
    try {
      final response = await _supabase.from(_tableName).select();
      return (response as List).map((e) => Worker.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch workers: $e');
    }
  }

  Future<List<Worker>> getWorkersBySite(String siteId) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .select()
          .eq('site_id', siteId);
      return (response as List).map((e) => Worker.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to fetch workers for site: $e');
    }
  }

  Future<Worker> getWorkerById(String id) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .select()
          .eq('id', id)
          .single();
      return Worker.fromJson(response);
    } catch (e) {
      throw Exception('Failed to fetch worker: $e');
    }
  }

  Future<Worker> createWorker(Worker worker) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .insert(worker.toJson())
          .select()
          .single();
      return Worker.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create worker: $e');
    }
  }

  Future<Worker> updateWorker(String id, Worker worker) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .update(worker.toJson())
          .eq('id', id)
          .select()
          .single();
      return Worker.fromJson(response);
    } catch (e) {
      throw Exception('Failed to update worker: $e');
    }
  }

  Future<void> deleteWorker(String id) async {
    try {
      await _supabase.from(_tableName).delete().eq('id', id);
    } catch (e) {
      throw Exception('Failed to delete worker: $e');
    }
  }
}
