import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../utils/storage_image_url.dart';

/// Network image that resolves Firebase Storage `gs://` URLs before loading.
class ResolvedNetworkImage extends StatefulWidget {
  const ResolvedNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;

  @override
  State<ResolvedNetworkImage> createState() => _ResolvedNetworkImageState();
}

class _ResolvedNetworkImageState extends State<ResolvedNetworkImage> {
  String? _resolvedUrl;
  String? _cacheKey;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ResolvedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrl.trim() != _cacheKey) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final raw = widget.imageUrl.trim();
    _cacheKey = raw;
    final url = await resolveStorageImageUrl(raw);
    if (mounted && _cacheKey == raw) {
      setState(() => _resolvedUrl = url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _resolvedUrl;
    if (url == null || url.isEmpty) {
      return errorWidget(context, widget.imageUrl, null);
    }

    return CachedNetworkImage(
      imageUrl: url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      placeholder: widget.placeholder,
      errorWidget: widget.errorWidget ?? errorWidget,
    );
  }

  Widget errorWidget(BuildContext context, String url, dynamic error) {
    if (widget.errorWidget != null) {
      return widget.errorWidget!(context, url, error);
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: const ColoredBox(
        color: Color(0xFFF3F4F6),
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: Color(0xFF9CA3AF)),
        ),
      ),
    );
  }
}
