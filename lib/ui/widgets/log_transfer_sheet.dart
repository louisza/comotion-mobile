// lib/ui/widgets/log_transfer_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../../services/log_transfer_service.dart';

/// Shows the log transfer screen as a full page route.
void showLogTransferSheet(
  BuildContext context, {
  required BluetoothDevice device,
  required String deviceId,
  String? matchId,
  String? playerId,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => LogTransferService(),
        child: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1A1A2E),
            title: const Text('Log Transfer'),
          ),
          body: _LogTransferContent(
            device: device,
            deviceId: deviceId,
            matchId: matchId,
            playerId: playerId,
          ),
        ),
      ),
    ),
  );
}

class _LogTransferContent extends StatefulWidget {
  final BluetoothDevice device;
  final String deviceId;
  final String? matchId;
  final String? playerId;

  const _LogTransferContent({
    required this.device,
    required this.deviceId,
    this.matchId,
    this.playerId,
  });

  @override
  State<_LogTransferContent> createState() => _LogTransferContentState();
}

class _LogTransferContentState extends State<_LogTransferContent> {
  bool _initialConnecting = true;
  final Set<String> _selectedFiles = {};

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final service = context.read<LogTransferService>();
    final ok = await service.connect(widget.device);
    if (ok) {
      await service.listFiles();
      await service.getStatus();
    }
    if (mounted) setState(() => _initialConnecting = false);
  }

  void _toggleSelection(String filename) {
    setState(() {
      if (_selectedFiles.contains(filename)) {
        _selectedFiles.remove(filename);
      } else {
        _selectedFiles.add(filename);
      }
    });
  }

  void _selectAll(List<LogFileInfo> files) {
    setState(() {
      if (_selectedFiles.length == files.length) {
        _selectedFiles.clear();
      } else {
        _selectedFiles.addAll(files.map((f) => f.filename));
      }
    });
  }

  Future<void> _downloadSelected(LogTransferService svc) async {
    for (final filename in _selectedFiles.toList()) {
      await svc.downloadAndUpload(
        matchId: widget.matchId ?? '',
        playerId: widget.playerId,
        deviceId: widget.deviceId,
      );
      // Small delay between files
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LogTransferService>(
      builder: (context, svc, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title row
              Row(
                children: [
                  const Icon(Icons.download_rounded, color: Colors.white, size: 24),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Download Logs',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  if (svc.isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bluetooth_connected, color: Color(0xFF4CAF50), size: 14),
                          SizedBox(width: 4),
                          Text('Connected', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.device.platformName.isNotEmpty ? widget.device.platformName : widget.deviceId,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),

              // SD card status
              if (svc.sdStatus != null) ...[
                const SizedBox(height: 8),
                _SdStatusBar(status: svc.sdStatus!),
              ],

              const SizedBox(height: 20),

              // Connection / loading state
              if (_initialConnecting || svc.state == TransferState.connecting)
                const _LoadingRow(text: 'Connecting to tracker...'),

              if (svc.state == TransferState.listing)
                const _LoadingRow(text: 'Listing files...'),

              // Error
              if (svc.state == TransferState.error) ...[
                _ErrorBanner(message: svc.errorMessage ?? 'Unknown error'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _connect(),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                    child: const Text('Retry'),
                  ),
                ),
              ],

              // Quick action: Download Latest & Upload
              if (svc.isConnected && svc.state == TransferState.idle && widget.matchId != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: const Text('Download Latest & Upload to Cloud'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => svc.downloadAndUpload(
                      matchId: widget.matchId!,
                      playerId: widget.playerId,
                      deviceId: widget.deviceId,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Download-only (no cloud) when no matchId
              if (svc.isConnected && svc.state == TransferState.idle && widget.matchId == null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download Latest Log'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => svc.downloadLatest(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Progress bar during download
              if (svc.state == TransferState.downloading) ...[
                _ProgressSection(
                  label: 'Downloading: ${svc.currentFile ?? "..."}',
                  progress: svc.progress,
                  detail: '${_formatBytes(svc.bytesReceived)} / ${_formatBytes(svc.expectedBytes)}',
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: svc.abort,
                    child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
                  ),
                ),
              ],

              // Uploading
              if (svc.state == TransferState.uploading)
                const _LoadingRow(text: 'Uploading to cloud...'),

              // Done
              if (svc.state == TransferState.done) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 24),
                      SizedBox(width: 12),
                      Expanded(child: Text(
                        'Upload complete! Data will appear on the dashboard shortly.',
                        style: TextStyle(color: Color(0xFF4CAF50)),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Offer to delete the file from tracker
                if (svc.currentFile != null && svc.currentFile != 'latest')
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text('Delete ${svc.currentFile} from tracker'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                      onPressed: () => svc.deleteFile(svc.currentFile!),
                    ),
                  ),
              ],

              // File list
              if (svc.availableFiles.isNotEmpty && svc.state == TransferState.idle) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Available Log Files',
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                    // Select all toggle
                    GestureDetector(
                      onTap: () => _selectAll(svc.availableFiles),
                      child: Text(
                        _selectedFiles.length == svc.availableFiles.length ? 'Deselect all' : 'Select all',
                        style: const TextStyle(color: Color(0xFF2196F3), fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._buildGroupedFiles(svc.availableFiles, svc, _selectedFiles, _toggleSelection),

                // Batch upload button when files are selected
                if (_selectedFiles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: Text('Upload ${_selectedFiles.length} selected file${_selectedFiles.length > 1 ? 's' : ''}'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        for (final filename in _selectedFiles.toList()) {
                          svc.downloadFile(filename);
                        }
                      },
                    ),
                  ),
                ],
              ],

              if (svc.isConnected && svc.availableFiles.isEmpty && svc.state == TransferState.idle)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('No log files on tracker', style: TextStyle(color: Colors.white38)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Sub-widgets ──

class _LoadingRow extends StatelessWidget {
  final String text;
  const _LoadingRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
          ),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
        ],
      ),
    );
  }
}

class _ProgressSection extends StatelessWidget {
  final String label;
  final double progress;
  final String detail;
  const _ProgressSection({required this.label, required this.progress, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 12,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(Color(0xFF2196F3)),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            Text(detail, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}

/// Group files by date and build date-header + file rows.
List<Widget> _buildGroupedFiles(
  List<LogFileInfo> files,
  LogTransferService svc,
  Set<String> selectedFiles,
  void Function(String) onToggleSelection,
) {
  // Sort: files with timestamps newest first, then files without timestamps by filename
  final withTime = files.where((f) => (f.startEpoch ?? 0) > 0).toList()
    ..sort((a, b) => (b.startEpoch ?? 0).compareTo(a.startEpoch ?? 0));
  final noTime = files.where((f) => (f.startEpoch ?? 0) <= 0).toList()
    ..sort((a, b) => a.filename.compareTo(b.filename));

  final sorted = [...withTime, ...noTime];
  final widgets = <Widget>[];
  String? lastDate;

  for (final f in sorted) {
    final date = f.dateLabel ?? 'Unknown date';
    if (date != lastDate) {
      lastDate = date;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(date,
            style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
      ));
    }
    widgets.add(_FileRow(
      file: f,
      isSelected: selectedFiles.contains(f.filename),
      onToggleSelect: () => onToggleSelection(f.filename),
      onDownload: () => svc.downloadFile(f.filename),
    ));
  }

  return widgets;
}

class _FileRow extends StatelessWidget {
  final LogFileInfo file;
  final bool isSelected;
  final VoidCallback onToggleSelect;
  final VoidCallback onDownload;
  const _FileRow({
    required this.file,
    required this.isSelected,
    required this.onToggleSelect,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final timeRange = file.timeRangeLabel;
    final duration = file.durationLabel;

    return GestureDetector(
      onTap: onToggleSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2196F3).withOpacity(0.12)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: const Color(0xFF2196F3).withOpacity(0.4), width: 1)
              : null,
        ),
        child: Row(
          children: [
            // Checkbox
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF2196F3) : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isSelected ? const Color(0xFF2196F3) : Colors.white24,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 10),
            // Time icon + duration
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    timeRange != null ? Icons.schedule : Icons.description_outlined,
                    color: timeRange != null ? const Color(0xFF2196F3) : Colors.white38,
                    size: 18,
                  ),
                  if (duration != null)
                    Text(duration,
                        style: const TextStyle(color: Colors.white54, fontSize: 9)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (timeRange != null)
                    Text(timeRange,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                  if (timeRange == null)
                    Text(file.filename,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    '${file.sizeFormatted} · ~${file.estimatedTime}${timeRange == null ? '' : ' · ${file.filename}'}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF2196F3)),
              onPressed: onDownload,
              iconSize: 22,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Download & upload',
            ),
          ],
        ),
      ),
    );
  }
}

class _SdStatusBar extends StatelessWidget {
  final String status;
  const _SdStatusBar({required this.status});

  @override
  Widget build(BuildContext context) {
    // Parse SD:<free_kb>,<total_kb>,<file_count>
    final parts = status.replaceFirst('SD:', '').split(',');
    if (parts.length < 3) return const SizedBox.shrink();

    final freeKb = int.tryParse(parts[0]) ?? 0;
    final totalKb = int.tryParse(parts[1]) ?? 0;
    final fileCount = int.tryParse(parts[2]) ?? 0;
    final usedPct = totalKb > 0 ? ((totalKb - freeKb) / totalKb) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.sd_card_outlined, color: Colors.white38, size: 16),
          const SizedBox(width: 6),
          Text('$fileCount files · ${_formatBytes(freeKb * 1024)} free',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const Spacer(),
          SizedBox(
            width: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: usedPct,
                minHeight: 4,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(
                  usedPct > 0.9 ? Colors.redAccent : Colors.white38,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes > 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  if (bytes > 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
