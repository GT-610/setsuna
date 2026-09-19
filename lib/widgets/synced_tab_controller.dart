import 'package:flutter/material.dart';

/// A [TabController] whose horizontal swipe animation matches the main
/// [PageView] navigation speed (677 ms, fastLinearToSlowEaseIn curve).
///
/// Use this anywhere a [TabBarView] should feel consistent with the primary
/// page transitions driven by [PageController.animateToPage].
class SyncedTabController extends TabController {
  SyncedTabController({
    required super.length,
    required super.vsync,
    super.initialIndex,
  }) : super(animationDuration: const Duration(milliseconds: 677));

  @override
  void animateTo(
    int value, {
    Duration? duration,
    Curve curve = Curves.ease,
  }) {
    super.animateTo(
      value,
      duration: duration ?? const Duration(milliseconds: 677),
      curve: Curves.fastLinearToSlowEaseIn,
    );
  }
}

/// A widget that creates and owns a [SyncedTabController], providing it to
/// descendants via [builder].  Useful in contexts (e.g. dialogs built with
/// [StatefulBuilder]) where you need a [TickerProvider] but don't have one.
class SyncedTabScope extends StatefulWidget {
  const SyncedTabScope({
    super.key,
    required this.tabCount,
    required this.builder,
  });

  final int tabCount;
  final Widget Function(BuildContext context, TabController controller) builder;

  @override
  State<SyncedTabScope> createState() => _SyncedTabScopeState();
}

class _SyncedTabScopeState extends State<SyncedTabScope>
    with SingleTickerProviderStateMixin {
  late final _controller = SyncedTabController(
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
