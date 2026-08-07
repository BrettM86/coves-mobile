/// Formatters shared by every media surface.
library;

/// Formats a video duration as `m:ss`, switching to `h:mm:ss` from one hour.
///
/// Total function: a negative duration reads as `0:00` rather than throwing,
/// since the value comes from an untrusted record.
String formatVideoDuration(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final paddedSeconds = (total % 60).toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
  }
  return '$minutes:$paddedSeconds';
}
