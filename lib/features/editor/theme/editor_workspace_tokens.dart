import 'package:flutter/material.dart';

/// Shared visual tokens for the notebook editor workspace chrome.
@immutable
class EditorWorkspaceTokens {
  const EditorWorkspaceTokens._();

  static const Color workspace = Color(0xFFF3F0E8);
  static const Color chrome = Color(0xFFFFFCF7);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFF2F6F73);
  static const Color selectedFill = Color(0xFFE7F3F3);
  static const Color selectedIndicator = Color(0xFF2F6F73);
  static const Color ink = Color(0xFF1E2526);
  static const Color divider = Color(0xFFDDD7CB);
  static const Color paperShadow = Color(0x1A1E2526);

  static const double chromeRadius = 12;
  static const double controlRadius = 8;

  /// Selected control tile size inside the 56px tool dock.
  static const double controlSize = 40;

  /// Vertical inset so selected tiles do not touch the dock edges.
  /// Paired with [controlSize] inside a 52px dock: 6 + 40 + 6.
  static const double controlInset = 6;
}
