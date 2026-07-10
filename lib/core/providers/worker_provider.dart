import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/worker.dart';
import '../../data/services/worker_service.dart';

part 'worker_provider.g.dart';

@riverpod
WorkerService workerService(Ref ref) => WorkerService();

@riverpod
Future<List<Worker>> allWorkers(Ref ref) async {
  final workerService = ref.watch(workerServiceProvider);
  return workerService.getAllWorkers();
}

@riverpod
Future<List<Worker>> workersBySite(Ref ref, String siteId) async {
  final workerService = ref.watch(workerServiceProvider);
  return workerService.getWorkersBySite(siteId);
}

@riverpod
Future<Worker> workerById(Ref ref, String workerId) async {
  final workerService = ref.watch(workerServiceProvider);
  return workerService.getWorkerById(workerId);
}
