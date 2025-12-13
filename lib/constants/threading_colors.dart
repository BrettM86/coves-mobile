import 'package:flutter/material.dart';

/// Color palette for comment threading depth indicators
///
/// These colors cycle through as threads get deeper, providing visual
/// distinction between nesting levels. Used by CommentCard and CommentThread.
const List<Color> kThreadingColors = [
  Color(0xFFFF6B6B), // Red
  Color(0xFF4ECDC4), // Teal
  Color(0xFFFFE66D), // Yellow
  Color(0xFF95E1D3), // Mint
  Color(0xFFC7CEEA), // Purple
  Color(0xFFFFAA5C), // Orange
];
