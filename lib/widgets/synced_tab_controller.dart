import 'package:flutter/material.dart';

import '../utils/app_motion.dart';

/// A [TabController] whose horizontal swipe animation matches the main
/// [PageView] navigation speed (see [kPageTransitionDuration]).
///
/// Use this anywhere a [TabBarView] should feel consistent with the primary
/// page transitions driven by [PageController.animateToPage].
class SyncedTabController extends TabController {
  SyncedTabController({
    required super.length,
    required super.vsync,
    super.initialIndex,
  }) : super(animationDuration: kPageTransitionDuration);

  @override
  void animateTo(int value, {Duration? duration, Curve? curve}) {
    super.animateTo(
      value,
      duration: duration ?? kPageTransitionDuration,
      curve: curve ?? kPageTransitionCurve,
    );
  }
}

/// A widget that creates and owns a [SyncedTabController], providing it to
/// descendants via [builder]. Useful in contexts (e.g. dialogs built with
/// [StatefulBuilder]) where you need a [TickerProvider] but don't have one.
///
/// When [tabCount] changes the controller and its subtree are rebuilt, so a
/// dynamic tab count (e.g. BT metadata adding the trackers/peers tabs) stays
/// valid, mirroring [DefaultTabController].
class SyncedTabScope extends StatelessWidget {
  const SyncedTabScope({
    super.key,
    required this.tabCount,
    required this.builder,
  });

  final int tabCount;
  final Widget Function(BuildContext context, TabController controller) builder;

  @override
  Widget build(BuildContext context) {
    return _SyncedTabScopeBody(
      // Remount the controller and everything below it when the count
      // changes; disposing a controller that a live TabBar still paints
      // with would otherwise crash.
      key: ValueKey<int>(tabCount),
      tabCount: tabCount,
      builder: builder,
    );
  }
}

class _SyncedTabScopeBody extends StatefulWidget {
  const _SyncedTabScopeBody({
    super.key,
    required this.tabCount,
    required this.builder,
  });

  final int tabCount;
  final Widget Function(BuildContext context, TabController controller) builder;

  @override
  State<_SyncedTabScopeBody> createState() => _SyncedTabScopeBodyState();
}

class _SyncedTabScopeBodyState extends State<_SyncedTabScopeBody>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = SyncedTabController(
    length: widget.tabCount,
    vsync: this,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _controller);
  }
}
