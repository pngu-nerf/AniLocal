import 'package:equatable/equatable.dart';

/// How much disk the app's data folder takes, by what it holds. Measured by
/// the data layer, shown by Settings › Maintenance; the UI never walks a
/// directory itself.
class CacheFootprint extends Equatable {
  const CacheFootprint({
    required this.databaseBytes,
    required this.artBytes,
    required this.logsBytes,
    required this.otherBytes,
  });

  /// `cache.sqlite` with its WAL, shm and journal sidecars.
  final int databaseBytes;

  /// The downloaded covers (`art/`).
  final int artBytes;

  /// The app log and its rotated backup (`logs/`).
  final int logsBytes;

  /// Everything else directly under the data folder: the cross-database id
  /// map, and any cache or covers a reset set aside (`*.broken-<stamp>`).
  final int otherBytes;

  int get totalBytes => databaseBytes + artBytes + logsBytes + otherBytes;

  @override
  List<Object?> get props => [databaseBytes, artBytes, logsBytes, otherBytes];
}

/// The ONE way a byte count becomes words in user copy. Decimal units, as
/// Finder shows them, so the number here matches the one the user sees when
/// they open the folder. Three significant figures: `48.2 MB`, `1.02 GB`,
/// `123 MB`; below a kilobyte, whole bytes.
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  const units = ['kB', 'MB', 'GB', 'TB'];
  var value = bytes / 1000;
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value >= 10
      ? value.toStringAsFixed(1)
      : value.toStringAsFixed(2);
  return '$text ${units[unit]}';
}
