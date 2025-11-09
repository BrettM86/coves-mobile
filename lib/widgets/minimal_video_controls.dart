import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../constants/app_colors.dart';

/// Minimal video controls showing only a scrubber/progress bar
///
/// Always visible at the bottom of the video, positioned above
/// the Android navigation bar using SafeArea.
class MinimalVideoControls extends StatefulWidget {
  const MinimalVideoControls({
    required this.controller,
    super.key,
  });

  final VideoPlayerController controller;

  @override
  State<MinimalVideoControls> createState() => _MinimalVideoControlsState();
}

class _MinimalVideoControlsState extends State<MinimalVideoControls> {
  double _sliderValue = 0;
  bool _isUserDragging = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateSlider);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateSlider);
    super.dispose();
  }

  void _updateSlider() {
    if (!_isUserDragging && mounted) {
      final position =
          widget.controller.value.position.inMilliseconds.toDouble();
      final duration =
          widget.controller.value.duration.inMilliseconds.toDouble();

      if (duration > 0) {
        setState(() {
          _sliderValue = position / duration;
        });
      }
    }
  }

  void _onSliderChanged(double value) {
    setState(() {
      _sliderValue = value;
    });
  }

  void _onSliderChangeStart(double value) {
    _isUserDragging = true;
  }

  void _onSliderChangeEnd(double value) {
    _isUserDragging = false;
    final duration = widget.controller.value.duration;
    final position = duration * value;
    widget.controller.seekTo(position);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.controller.value.position;
    final duration = widget.controller.value.duration;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.black.withValues(alpha: 0),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scrubber slider
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.3),
            ),
            child: Slider(
              value: _sliderValue.clamp(0, 1.0),
              onChanged: _onSliderChanged,
              onChangeStart: _onSliderChangeStart,
              onChangeEnd: _onSliderChangeEnd,
            ),
          ),
          // Time labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
