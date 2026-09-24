import 'package:flutter/material.dart';

/// The "happening right now" accent.
///
/// Shared rather than written twice, because two things are deliberately the
/// same colour: the line marking the current minute on the timeline, and the
/// "Plan my day" button that sits over it. Duplicating the literal in both
/// files is how they would quietly drift apart the next time either is
/// adjusted.
///
/// It is intentionally the one warm colour in an otherwise blue and white app,
/// so it reads as "now" against everything else on the screen.
const Color kNowAccent = Color(0xFFFF8FA3);
