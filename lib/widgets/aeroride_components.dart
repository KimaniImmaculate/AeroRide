import 'package:flutter/material.dart';
import '../theme/aeroride_theme.dart';
import '../utils/currency.dart';

class AeroRideGradientShell extends StatelessWidget {
  final Widget child;
  final Gradient? gradient;

  const AeroRideGradientShell({super.key, required this.child, this.gradient});

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient ?? tokens.oceanGradient),
      child: child,
    );
  }
}

class AeroRidePanelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;

  const AeroRidePanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? tokens.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: tokens.mutedBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120D2B52),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class AeroRideSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const AeroRideSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: tokens.primaryDarkBlue,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class AeroRidePillButton extends StatelessWidget {
  final String label;
  final Widget? icon;
  final bool selected;
  final VoidCallback? onTap;

  const AeroRidePillButton({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? tokens.primaryDarkBlue
              : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? tokens.primaryDarkBlue : tokens.mutedBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final iconWidget?) ...[
              iconWidget,
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : tokens.primaryDarkBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AeroRideTextField extends StatelessWidget {
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final bool obscureText;

  const AeroRideTextField({
    super.key,
    required this.hint,
    required this.icon,
    required this.controller,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: tokens.primaryDarkBlue),
        filled: true,
        fillColor: tokens.softSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: tokens.mutedBorder),
        ),
      ),
    );
  }
}

class AeroRidePrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Widget? trailing;

  const AeroRidePrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? tokens.primaryDarkBlue,
          foregroundColor: foregroundColor ?? Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class AeroRideRideTypeCard extends StatelessWidget {
  final String title;
  final String price;
  final String eta;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const AeroRideRideTypeCard({
    super.key,
    required this.title,
    required this.price,
    required this.eta,
    required this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 150,
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF8FBFF) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? tokens.primaryDarkBlue : tokens.mutedBorder,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: tokens.primaryDarkBlue, size: 21),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
            Text(
              price,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.primaryDarkBlue,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            Text(
              eta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class AeroRideInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const AeroRideInfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: tokens.primaryDarkBlue,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class AeroRideMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? accentColor;

  const AeroRideMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tokens.mutedBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: accentColor ?? tokens.primaryDarkBlue,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class AeroRideStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const AeroRideStatusPill({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14), // Already correct
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class AeroRideTimeline extends StatelessWidget {
  final List<AeroRideTimelineStep> steps;

  const AeroRideTimeline({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Column(
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: steps[index].completed
                          ? tokens.successGreen
                          : tokens.primaryDarkBlue,
                    ),
                  ),
                  if (index != steps.length - 1)
                    Container(width: 2, height: 52, color: tokens.mutedBorder),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        steps[index].title,
                        style: TextStyle(
                          color: tokens.primaryDarkBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        steps[index].subtitle,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class AeroRideTimelineStep {
  final String title;
  final String subtitle;
  final bool completed;

  const AeroRideTimelineStep({
    required this.title,
    required this.subtitle,
    this.completed = false,
  });
}

class AeroRideTipSelector extends StatelessWidget {
  final List<double> tips;
  final double selectedTip;
  final ValueChanged<double> onChanged;

  const AeroRideTipSelector({
    super.key,
    required this.tips,
    required this.selectedTip,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Row(
      children: [
        for (final tip in tips)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => onChanged(tip),
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: tip == selectedTip
                        ? tokens.primaryDarkBlue
                        : tokens.softSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: tip == selectedTip
                          ? tokens.primaryDarkBlue
                          : tokens.mutedBorder,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      formatKES(tip),
                      style: TextStyle(
                        color: tip == selectedTip
                            ? Colors.white
                            : tokens.primaryDarkBlue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AeroRidePaymentOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final Widget? trailing;

  const AeroRidePaymentOption({
    super.key,
    required this.label,
    required this.subtitle,
    this.selected = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFF8FBFF) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? tokens.primaryDarkBlue : tokens.mutedBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: tokens.primaryDarkBlue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class AeroRideMapShell extends StatelessWidget {
  final Widget map;
  final List<Widget> overlays;

  const AeroRideMapShell({
    super.key,
    required this.map,
    required this.overlays,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: map),
        ...overlays,
      ],
    );
  }
}
