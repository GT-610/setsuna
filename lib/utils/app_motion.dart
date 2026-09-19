import 'package:flutter/animation.dart';

/// Shared motion tokens for the primary horizontal navigation transition.
///
/// The main `PageView` and every `TabBarView` backed by `SyncedTabController`
/// use these values, so paging and tab switching stay visually identical and
/// only have to be tuned in one place.
const Duration kPageTransitionDuration = Duration(milliseconds: 677);
const Curve kPageTransitionCurve = Curves.fastLinearToSlowEaseIn;
