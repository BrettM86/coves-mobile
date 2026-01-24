import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_colors.dart';

/// A modal bottom sheet for selecting an image source (gallery or camera).
///
/// Usage:
/// ```dart
/// final source = await ImageSourcePicker.show(context);
/// if (source != null) {
///   // Pick image using the selected source
/// }
/// ```
abstract final class ImageSourcePicker {
  /// Shows the image source picker modal and returns the selected source.
  ///
  /// Returns [ImageSource.gallery], [ImageSource.camera], or null if cancelled.
  static Future<ImageSource?> show(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const _ImageSourcePickerSheet(),
    );
  }
}

class _ImageSourcePickerSheet extends StatelessWidget {
  const _ImageSourcePickerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Select Image Source',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.photo_library,
                  color: AppColors.primary,
                ),
              ),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Select an existing photo',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: AppColors.teal,
                ),
              ),
              title: const Text(
                'Take a Photo',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Use camera to capture',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
