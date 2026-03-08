// lib/services/log_transfer_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;

import 'cloud_config.dart';

/// Nordic UART Service UUIDs.
const String _nusServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String _nusRxCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
const String _nusTxCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

/// Info about a log file on the tracker SD card.
class LogFileInfo {
  final String filename;
  final int bytes;
  final String? timestamp;
  final int? startEpoch; // First GPS timestamp in the log
  final int? endEpoch;   // Last GPS timestamp in the log

  LogFileInfo({
    required this.filename,
    required this.bytes,
    this.timestamp,
    this.startEpoch,
    this.endEpoch,
  });

  String get sizeFormatted {
    if (bytes > 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes > 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  /// Estimated transfer time at ~5KB/s BLE throughput.
  String get estimatedTime {
    final seconds = bytes / 5000;
    if (seconds < 60) return '${seconds.toStringAsFixed(0)}s';
    return '${(seconds / 60).toStringAsFixed(1)} min';
  }

  /// Human-readable start date/time (e.g. "8 Mar 14:30").
  String? get startLabel => startEpoch != null && startEpoch! > 0
      ? _formatEpoch(startEpoch!)
      : null;

  /// Human-readable end date/time.
  String? get endLabel => endEpoch != null && endEpoch! > 0
      ? _formatEpoch(endEpoch!)
      : null;

  /// Duration of the logging session.
  String? get durationLabel {
    if (startEpoch == null || endEpoch == null || startEpoch! <= 0 || endEpoch! <= 0) return null;
    final dur = endEpoch! - startEpoch!;
    if (dur <= 0) return null;
    final mins = dur ~/ 60;
    if (mins < 60) return '${mins} min';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  /// Date label for grouping (e.g. "8 Mar 2026").
  String? get dateLabel {
    if (startEpoch == null || startEpoch! <= 0) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(startEpoch! * 1000, isUtc: true).toLocal();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  /// Time range label (e.g. "14:30 – 15:45").
  String? get timeRangeLabel {
    final s = startLabel;
    final e = endLabel;
    if (s == null) return null;
    // Extract just the time portion
    final sTime = _formatTime(startEpoch!);
    final eTime = endEpoch != null && endEpoch! > 0 ? _formatTime(endEpoch!) : null;
    if (eTime != null) return '$sTime – $eTime';
    return sTime;
  }

  static String _formatEpoch(int epoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true).toLocal();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _formatTime(int epoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// States of the transfer pipeline.
enum TransferState {
  idle,
  connecting,
  listing,
  downloading,
  uploading,
  done,
  error,
}

/// Service that handles BLE log download from tracker and upload to cloud.
///
/// Usage:
///   1. Call [connect] with the BluetoothDevice
///   2. Call [listFiles] to see available logs
///   3. Call [downloadAndUpload] for one-tap transfer
///   4. Call [disconnect] when done
class LogTransferService extends ChangeNotifier {
  TransferState _state = TransferState.idle;
  double _progress = 0.0;
  String? _currentFile;
  String? _errorMessage;
  List<LogFileInfo> _availableFiles = [];
  int _bytesReceived = 0;
  int _expectedBytes = 0;
  String? _sdStatus;

  // BLE connection state
  BluetoothDevice? _device;
  BluetoothCharacteristic? _nusRx;
  BluetoothCharacteristic? _nusTx;
  StreamSubscription? _notifySub;

  // Transfer buffer
  final List<int> _downloadBuffer = [];
  int _lastAckSeq = 0;
  Completer<void>? _transferCompleter;
  Completer<void>? _listCompleter;

  // Getters
  TransferState get state => _state;
  double get progress => _progress;
  String? get currentFile => _currentFile;
  String? get errorMessage => _errorMessage;
  List<LogFileInfo> get availableFiles => List.unmodifiable(_availableFiles);
  int get bytesReceived => _bytesReceived;
  int get expectedBytes => _expectedBytes;
  String? get sdStatus => _sdStatus;
  bool get isConnected => _nusRx != null && _nusTx != null;

  void _setState(TransferState s) {
    _state = s;
    notifyListeners();
  }

  /// Connect to a tracker's NUS service.
  Future<bool> connect(BluetoothDevice device) async {
    try {
      _setState(TransferState.connecting);
      _device = device;

      debugPrint('[LogTransfer] Connecting to ${device.platformName}...');
      
      // Android requires stopping BLE scan before connecting
      if (FlutterBluePlus.isScanningNow) {
        debugPrint('[LogTransfer] Stopping BLE scan before connect...');
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      await device.connect(timeout: const Duration(seconds: 10), autoConnect: false);

      // Request larger MTU for faster transfers
      try {
        await device.requestMtu(251);
        debugPrint('[LogTransfer] MTU requested: 251');
      } catch (_) {}

      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == _nusServiceUuid) {
          for (final char in svc.characteristics) {
            final uuid = char.uuid.toString().toLowerCase();
            if (uuid == _nusRxCharUuid) _nusRx = char;
            if (uuid == _nusTxCharUuid) _nusTx = char;
          }
        }
      }

      if (_nusRx == null || _nusTx == null) {
        _errorMessage = 'NUS service not found on device';
        _setState(TransferState.error);
        await device.disconnect();
        return false;
      }

      // Subscribe to NUS TX notifications (tracker → phone)
      await _nusTx!.setNotifyValue(true);
      _notifySub = _nusTx!.onValueReceived.listen(_onNusData);

      debugPrint('[LogTransfer] Connected + NUS ready');
      _setState(TransferState.idle);
      return true;
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _setState(TransferState.error);
      return false;
    }
  }

  /// Disconnect from the tracker.
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _nusRx = null;
    _nusTx = null;
    _device = null;
    _setState(TransferState.idle);
  }

  /// Send a command string over NUS RX.
  Future<void> _sendCommand(String cmd) async {
    if (_nusRx == null) return;
    debugPrint('[LogTransfer] TX: $cmd');
    await _nusRx!.write(
      Uint8List.fromList(utf8.encode(cmd)),
      withoutResponse: false,
    );
  }

  /// List available log files on the tracker SD card.
  Future<List<LogFileInfo>> listFiles() async {
    if (!isConnected) throw StateError('Not connected');

    _availableFiles = [];
    _setState(TransferState.listing);

    _listCompleter = Completer<void>();
    await _sendCommand('LIST\n');

    // Wait for END_LIST or timeout
    await _listCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('[LogTransfer] LIST timeout');
      },
    );

    _listCompleter = null;
    _setState(TransferState.idle);
    return _availableFiles;
  }

  /// Get SD card status (free space, file count).
  Future<void> getStatus() async {
    if (!isConnected) return;
    await _sendCommand('STATUS\n');
  }

  /// Download a specific log file from the tracker.
  Future<List<int>> downloadFile(String filename) async {
    if (!isConnected) throw StateError('Not connected');

    _currentFile = filename;
    _downloadBuffer.clear();
    _bytesReceived = 0;
    _expectedBytes = 0;
    _lastAckSeq = 0;
    _progress = 0.0;
    _setState(TransferState.downloading);

    _transferCompleter = Completer<void>();
    await _sendCommand('DUMP:$filename\n');

    // Wait for END_DUMP or timeout (generous: 15 min for large files)
    await _transferCompleter!.future.timeout(
      const Duration(minutes: 15),
      onTimeout: () {
        _errorMessage = 'Transfer timed out';
        _setState(TransferState.error);
      },
    );

    _transferCompleter = null;
    return List<int>.from(_downloadBuffer);
  }

  /// Download the latest log file.
  Future<List<int>> downloadLatest() async {
    if (!isConnected) throw StateError('Not connected');

    _currentFile = 'latest';
    _downloadBuffer.clear();
    _bytesReceived = 0;
    _expectedBytes = 0;
    _lastAckSeq = 0;
    _progress = 0.0;
    _setState(TransferState.downloading);

    _transferCompleter = Completer<void>();
    await _sendCommand('DUMP_LATEST\n');

    await _transferCompleter!.future.timeout(
      const Duration(minutes: 15),
      onTimeout: () {
        _errorMessage = 'Transfer timed out';
        _setState(TransferState.error);
      },
    );

    _transferCompleter = null;
    return List<int>.from(_downloadBuffer);
  }

  /// Delete a file from the tracker (after successful upload).
  Future<bool> deleteFile(String filename) async {
    if (!isConnected) return false;
    await _sendCommand('DELETE:$filename\n');
    // Response handled in _onNusData
    return true;
  }

  /// Abort an in-progress transfer.
  Future<void> abort() async {
    await _sendCommand('ABORT\n');
    _transferCompleter?.complete();
    _transferCompleter = null;
    _setState(TransferState.idle);
  }

  /// One-tap: download latest log and upload to cloud.
  Future<void> downloadAndUpload({
    required String matchId,
    String? playerId,
    String? deviceId,
  }) async {
    try {
      // 1. Download
      final bytes = await downloadLatest();
      if (bytes.isEmpty) {
        _errorMessage = 'No data received';
        _setState(TransferState.error);
        return;
      }

      // 2. Decompress if gzipped (first two bytes: 0x1F 0x8B)
      List<int> csvBytes;
      if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
        debugPrint('[LogTransfer] Decompressing gzipped data...');
        csvBytes = gzip.decode(bytes);
      } else {
        csvBytes = bytes;
      }

      debugPrint('[LogTransfer] CSV size: ${csvBytes.length} bytes');

      // 3. Upload to cloud
      _setState(TransferState.uploading);
      await _uploadToCloud(
        matchId: matchId,
        playerId: playerId,
        deviceId: deviceId,
        csvBytes: csvBytes,
        filename: _currentFile ?? 'tracker_log.csv',
      );

      _setState(TransferState.done);
    } catch (e) {
      _errorMessage = 'Transfer failed: $e';
      _setState(TransferState.error);
    }
  }

  /// Upload CSV bytes to the Comotion web API.
  Future<void> _uploadToCloud({
    required String matchId,
    String? playerId,
    String? deviceId,
    required List<int> csvBytes,
    required String filename,
  }) async {
    final baseUrl = CloudConfig.apiBaseUrl;
    if (baseUrl.isEmpty) throw StateError('Cloud API not configured');

    final params = <String, String>{};
    if (playerId != null) params['player_id'] = playerId;
    if (deviceId != null) params['device_id'] = deviceId;

    final qs = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';

    final uri = Uri.parse('$baseUrl/api/v1/matches/$matchId/upload$qs');
    debugPrint('[LogTransfer] Uploading to $uri (${csvBytes.length} bytes)');

    final request = http.MultipartRequest('POST', uri)
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        csvBytes,
        filename: filename.endsWith('.csv') ? filename : '$filename.csv',
      ));

    // Add auth token if available
    final token = CloudConfig.authToken;
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw Exception('Upload failed (${response.statusCode}): $body');
    }

    debugPrint('[LogTransfer] ✅ Upload complete');
  }

  // ── NUS Notification Handler ──

  /// Accumulator for partial NUS messages (text responses may be split across
  /// multiple BLE notifications).
  String _nusTextBuffer = '';

  void _onNusData(List<int> data) {
    // During binary download, data is chunks (seq + payload)
    if (_state == TransferState.downloading && _expectedBytes > 0) {
      // Check if this is a text message (END_DUMP footer)
      final str = utf8.decode(data, allowMalformed: true);
      if (str.startsWith('END_DUMP:')) {
        _onTextMessage(str.trim());
        return;
      }

      // Binary chunk: [seq_u16_le][payload]
      if (data.length >= 3) {
        final seq = data[0] | (data[1] << 8);
        _downloadBuffer.addAll(data.sublist(2));
        _bytesReceived = _downloadBuffer.length;
        _progress = _expectedBytes > 0
            ? (_bytesReceived / _expectedBytes).clamp(0.0, 1.0)
            : 0.0;

        // ACK every 50 chunks
        if (seq - _lastAckSeq >= 50) {
          _sendCommand('ACK:$seq\n');
          _lastAckSeq = seq;
        }

        notifyListeners();
      }
      return;
    }

    // Text mode: accumulate until newline
    _nusTextBuffer += utf8.decode(data, allowMalformed: true);
    while (_nusTextBuffer.contains('\n')) {
      final idx = _nusTextBuffer.indexOf('\n');
      final line = _nusTextBuffer.substring(0, idx).trim();
      _nusTextBuffer = _nusTextBuffer.substring(idx + 1);
      if (line.isNotEmpty) _onTextMessage(line);
    }
  }

  void _onTextMessage(String msg) {
    debugPrint('[LogTransfer] RX: $msg');

    if (msg.startsWith('FILE:')) {
      // Parse file listing: FILE:<filename>,<bytes>,<start_epoch>,<end_epoch>
      final parts = msg.substring(5).split(',');
      if (parts.length >= 2) {
        _availableFiles.add(LogFileInfo(
          filename: parts[0].trim(),
          bytes: int.tryParse(parts[1].trim()) ?? 0,
          timestamp: parts.length > 2 ? parts[2].trim() : null,
          startEpoch: parts.length > 2 ? int.tryParse(parts[2].trim()) : null,
          endEpoch: parts.length > 3 ? int.tryParse(parts[3].trim()) : null,
        ));
        notifyListeners();
      }
    } else if (msg.startsWith('END_LIST')) {
      _listCompleter?.complete();
    } else if (msg.startsWith('XFER:')) {
      // Transfer header: XFER:<filename>,<total_bytes>,<crc32>
      final parts = msg.substring(5).split(',');
      if (parts.length >= 2) {
        _currentFile = parts[0].trim();
        _expectedBytes = int.tryParse(parts[1].trim()) ?? 0;
        debugPrint('[LogTransfer] Transfer started: $_currentFile, $_expectedBytes bytes');
      }
    } else if (msg.startsWith('END_DUMP:')) {
      // Transfer complete: END_DUMP:<actual_bytes>,<actual_crc32>
      final parts = msg.substring(9).split(',');
      final actualBytes = int.tryParse(parts[0].trim()) ?? 0;
      debugPrint('[LogTransfer] Transfer complete: $actualBytes bytes received, buffer: ${_downloadBuffer.length}');
      // TODO: verify CRC32
      _transferCompleter?.complete();
    } else if (msg.startsWith('SD:')) {
      // SD status: SD:<free_kb>,<total_kb>,<file_count>
      _sdStatus = msg;
      notifyListeners();
    } else if (msg == 'OK') {
      debugPrint('[LogTransfer] Command OK');
    } else if (msg.startsWith('ERR:')) {
      _errorMessage = msg.substring(4);
      _setState(TransferState.error);
      _transferCompleter?.complete();
      _listCompleter?.complete();
    }
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
