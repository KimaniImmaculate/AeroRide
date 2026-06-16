import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// A reusable utility to wrap any widget with a shimmering effect.
class ShimmerPlaceholder extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerPlaceholder({
    super.key,
    required this.child,
    this.enabled = true,
    this.baseColor,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return RepaintBoundary(
      child: Shimmer.fromColors(
        baseColor: baseColor ?? Colors.white.withOpacity(0.12),
        highlightColor: highlightColor ?? Colors.white.withOpacity(0.35),
        period: const Duration(
            milliseconds: 2000), // Slightly slower is easier on CPU
        child: child,
      ),
    );
  }
}

/// Specific layout for a Ride Type Card Skeleton
class RideTypeSkeleton extends StatelessWidget {
  const RideTypeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(width: 48, height: 48, color: Colors.white),
      title: Container(width: double.infinity, height: 12, color: Colors.white),
      subtitle: Container(width: 150, height: 10, color: Colors.white),
      trailing: Container(width: 40, height: 20, color: Colors.white),
    );
  }
}

/// A specialized widget for loading local assets with a skeleton transition.
class AssetImageSkeleton extends StatelessWidget {
  final String assetPath;
  final double width;
  final double height;
  final BoxFit fit;

  const AssetImageSkeleton({
    super.key,
    required this.assetPath,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      // The frameBuilder handles the transition from nothing/skeleton to the image
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return ShimmerPlaceholder(
          child: Container(width: width, height: height, color: Colors.white),
        );
      },
    );
  }
}

/// A specialized widget for full-screen background assets.
/// It handles the transition from a shimmer to the actual image to prevent white flashes.
class ShimmerBackground extends StatelessWidget {
  final String assetPath;
  final Widget? child;
  final double opacity;

  const ShimmerBackground({
    super.key,
    required this.assetPath,
    this.child,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The Shimmer Layer (Bottom)
        ShimmerPlaceholder(
          child: Container(color: Colors.white),
        ),
        // The Actual Image (Middle)
        Image.asset(
          assetPath,
          fit: BoxFit.cover,
          opacity: AlwaysStoppedAnimation(opacity),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              child: child,
            );
          },
        ),
        // Content Layer (Top)
        if (child != null) child!,
      ],
    );
  }
}
