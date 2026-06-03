import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Segmented control: each segment paints its own white pill when selected (no sliding thumb).
class AnimatedSegmentedTabBar extends StatelessWidget {
  final TabController controller;
  final List<String> labels;
  final EdgeInsetsGeometry? padding;

  const AnimatedSegmentedTabBar({
    super.key,
    required this.controller,
    required this.labels,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    assert(labels.length >= 2);
    assert(labels.length == controller.length);

    final bar = ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final selectedIndex = controller.index;

        return Container(
          height: 44,
          padding: const EdgeInsets.all(4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.chipBg,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: List.generate(
              labels.length,
              (index) => Expanded(
                child: _SegmentCell(
                  label: labels[index],
                  isSelected: index == selectedIndex,
                  onTap: () {
                    if (controller.index != index) {
                      controller.index = index;
                    }
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    if (padding == null) return bar;
    return Padding(padding: padding!, child: bar);
  }
}

class _SegmentCell extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentCell({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  static const _segmentShadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 6,
      offset: Offset(0, 1),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isSelected ? _segmentShadow : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.5,
            color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
