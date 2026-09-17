import 'package:setsuna/models/aria2_instance.dart';
import 'package:setsuna/services/aria2_rpc_client.dart';

class FakeRpcClient implements Aria2RpcClient {
  Future<Map<String, dynamic>> Function()? options;
  Future<String> Function(List<String>, Map<String, dynamic>)? add;
  Future<String?> Function(String)? status;
  Future<String> Function(String)? remove;
  Future<String> Function(String)? removeResult;
  Future<bool> Function()? save;

  @override
  Future<Map<String, dynamic>> getOption(String gid) async =>
      await options?.call() ?? <String, dynamic>{};
  @override
  Future<String> addUri(List<String> uris, [Map<String, dynamic>? options]) =>
      add!(uris, options ?? <String, dynamic>{});
  @override
  Future<Map<String, dynamic>> getTaskStatus(String gid) async =>
      <String, dynamic>{'status': await status?.call(gid) ?? 'active'};
  @override
  Future<String> removeTask(String gid, {bool force = false}) async =>
      await remove?.call(gid) ?? gid;
  @override
  Future<String> removeDownloadResult(String gid) async =>
      await removeResult?.call(gid) ?? 'OK';
  @override
  Future<bool> saveSession() async => await save?.call() ?? true;
  @override
  Future<void> close() async {}
  @override
  Aria2Instance get instance => Aria2Instance(
    id: 'test',
    name: 'Test',
    type: InstanceType.remote,
    protocol: 'http',
    host: '127.0.0.1',
    port: 6800,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
