import '../enums.dart';

class DownloadTask {
  final String id;
  final String name;
  final DownloadStatus status;
  final String? taskStatus;
  final double progress;
  final String downloadSpeed;
  final String uploadSpeed;
  final String size;
  final String completedSize;
  final bool isLocal;
  final String instanceId;

  String get key => '$instanceId::$id';
  final int? connections;
  final int? numSeeders;
  final String? dir;
  final int totalLengthBytes;
  final int completedLengthBytes;
  final int uploadLengthBytes;
  final int downloadSpeedBytes;
  final int uploadSpeedBytes;
  final List<Map<String, dynamic>>? files;
  final String? bittorrentInfo;
  final List<String>? trackers;
  final List<String>? uris;
  final String? errorMessage;
  final DateTime? startTime;
  final String? bitfield;
  final String? infoHash;
  final int? pieceLength;
  final int? numPieces;
  final bool isSeeder;

  DownloadTask({
    required this.id,
    required this.name,
    required this.status,
    this.taskStatus,
    required this.progress,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.size,
    required this.completedSize,
    required this.isLocal,
    required this.instanceId,
    this.connections,
    this.numSeeders,
    this.dir,
    this.totalLengthBytes = 0,
    this.completedLengthBytes = 0,
    this.uploadLengthBytes = 0,
    this.downloadSpeedBytes = 0,
    this.uploadSpeedBytes = 0,
    this.files,
    this.bittorrentInfo,
    this.trackers,
    this.uris,
    this.errorMessage,
    this.startTime,
    this.bitfield,
    this.infoHash,
    this.pieceLength,
    this.numPieces,
    this.isSeeder = false,
  });

  /// Compares observable task data so unchanged polling results can be reused.
  bool sameContentAs(DownloadTask other) =>
      id == other.id &&
      name == other.name &&
      status == other.status &&
      taskStatus == other.taskStatus &&
      progress == other.progress &&
      downloadSpeed == other.downloadSpeed &&
      uploadSpeed == other.uploadSpeed &&
      size == other.size &&
      completedSize == other.completedSize &&
      isLocal == other.isLocal &&
      instanceId == other.instanceId &&
      connections == other.connections &&
      numSeeders == other.numSeeders &&
      dir == other.dir &&
      totalLengthBytes == other.totalLengthBytes &&
      completedLengthBytes == other.completedLengthBytes &&
      uploadLengthBytes == other.uploadLengthBytes &&
      downloadSpeedBytes == other.downloadSpeedBytes &&
      uploadSpeedBytes == other.uploadSpeedBytes &&
      _equalValues(files, other.files) &&
      bittorrentInfo == other.bittorrentInfo &&
      _equalValues(trackers, other.trackers) &&
      _equalValues(uris, other.uris) &&
      errorMessage == other.errorMessage &&
      startTime == other.startTime &&
      bitfield == other.bitfield &&
      infoHash == other.infoHash &&
      pieceLength == other.pieceLength &&
      numPieces == other.numPieces &&
      isSeeder == other.isSeeder;

  static bool _equalValues(Object? left, Object? right) {
    if (identical(left, right)) return true;
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!_equalValues(left[i], right[i])) return false;
      }
      return true;
    }
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every(
            (key) =>
                right.containsKey(key) && _equalValues(left[key], right[key]),
          );
    }
    return left == right;
  }
}
