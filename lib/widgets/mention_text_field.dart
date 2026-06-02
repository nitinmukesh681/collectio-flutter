import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/comment_mentions.dart';
import '../widgets/avatar_fallback.dart';

class MentionTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final int minLines;
  final int maxLines;
  final bool filled;
  final bool dense;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? textStyle;
  final TextAlignVertical? textAlignVertical;
  final bool collapseDecoration;
  final FirestoreService firestoreService;
  final Color? accentColor;
  final Widget Function(Widget textField)? surroundBuilder;

  const MentionTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.firestoreService,
    this.hintText = 'Add a comment...',
    this.minLines = 1,
    this.maxLines = 4,
    this.filled = false,
    this.dense = false,
    this.contentPadding,
    this.textStyle,
    this.textAlignVertical,
    this.collapseDecoration = false,
    this.accentColor,
    this.surroundBuilder,
  });

  @override
  State<MentionTextField> createState() => _MentionTextFieldState();
}

class _MentionTextFieldState extends State<MentionTextField> {
  static const int _maxVisibleSuggestions = 5;
  static const double _suggestionRowHeight = 52;

  List<UserEntity> _suggestions = const [];
  final List<CommentMention> _confirmedMentions = [];
  bool _showSuggestions = false;
  Timer? _debounce;
  Timer? _hideDelayTimer;
  int _mentionStartIndex = -1;
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _anchorKey = GlobalKey();
  double? _anchorWidth;
  OverlayEntry? _overlayEntry;

  double get _panelHeight =>
      math.min(_suggestions.length, _maxVisibleSuggestions) * _suggestionRowHeight;

  TextStyle get _baseTextStyle =>
      widget.textStyle ??
      GoogleFonts.plusJakartaSans(
        fontSize: 14,
        color: AppColors.textPrimary,
        height: 1.45,
      );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChanged);
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideDelayTimer?.cancel();
    _removeOverlay();
    widget.controller.removeListener(_handleTextChanged);
    widget.focusNode.removeListener(_handleFocusChanged);
    super.dispose();
  }

  void _scheduleAnchorMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final width = box.size.width;
      if (width != _anchorWidth) {
        setState(() => _anchorWidth = width);
        _overlayEntry?.markNeedsBuild();
      }
    });
  }

  void _handleFocusChanged() {
    if (widget.focusNode.hasFocus) {
      _hideDelayTimer?.cancel();
      _handleTextChanged();
      return;
    }

    _hideDelayTimer?.cancel();
    _hideDelayTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || widget.focusNode.hasFocus) return;
      _hideSuggestions();
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _syncOverlay() {
    if (!_showSuggestions || _suggestions.isEmpty || !mounted) {
      _removeOverlay();
      return;
    }

    if (_overlayEntry == null) {
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return;

      _overlayEntry = OverlayEntry(
        builder: (context) => _buildOverlaySuggestions(),
      );
      overlay.insert(_overlayEntry!);
    } else {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _hideSuggestions() {
    _debounce?.cancel();
    _hideDelayTimer?.cancel();
    _removeOverlay();
    if (!_showSuggestions && _suggestions.isEmpty) return;
    setState(() {
      _showSuggestions = false;
      _suggestions = const [];
    });
  }

  void _syncConfirmedMentions(String text) {
    _confirmedMentions.removeWhere(
      (mention) => !text.contains('@${mention.username}'),
    );
  }

  void _handleTextChanged() {
    final text = widget.controller.text;
    _syncConfirmedMentions(text);

    final cursor = widget.controller.selection.baseOffset;
    final query = CommentMentions.activeMentionQuery(text, cursor);
    final startIndex = CommentMentions.activeMentionStartIndex(text, cursor);

    if (query == null || startIndex == null) {
      _hideSuggestions();
      if (mounted) setState(() {});
      return;
    }

    _mentionStartIndex = startIndex;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      List<UserEntity> results = const [];
      try {
        results = await widget.firestoreService.getMentionUserSuggestions(query);
      } catch (e) {
        debugPrint('Mention suggestion lookup failed: $e');
      }

      if (!mounted) return;

      final stillActive = CommentMentions.activeMentionQuery(
            widget.controller.text,
            widget.controller.selection.baseOffset,
          ) !=
          null;

      if (!stillActive) {
        _hideSuggestions();
        if (mounted) setState(() {});
        return;
      }

      setState(() {
        _suggestions = results;
        _showSuggestions = results.isNotEmpty;
      });

      if (results.isEmpty) {
        _removeOverlay();
        return;
      }

      _scheduleAnchorMeasure();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncOverlay();
      });
    });

    if (mounted) setState(() {});
  }

  void _insertMention(UserEntity user) {
    _hideDelayTimer?.cancel();

    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    final startIndex = _mentionStartIndex >= 0 ? _mentionStartIndex : text.lastIndexOf('@', cursor);

    if (startIndex < 0) return;

    final before = text.substring(0, startIndex);
    final after = text.substring(cursor);
    final mention = '@${user.username} ';
    final updated = '$before$mention$after';

    _confirmedMentions.removeWhere(
      (existing) => existing.username.toLowerCase() == user.username.toLowerCase(),
    );
    _confirmedMentions.add(CommentMention(userId: user.id, username: user.username));

    widget.controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: before.length + mention.length),
    );

    _hideSuggestions();
    widget.focusNode.requestFocus();
    setState(() {});
  }

  EdgeInsetsGeometry get _contentPadding {
    if (widget.contentPadding != null) return widget.contentPadding!;
    if (widget.filled) {
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    }
    return EdgeInsets.symmetric(horizontal: 0, vertical: widget.dense ? 0 : 10);
  }

  Widget _buildSuggestionTile(UserEntity user) {
    return InkWell(
      onTap: () => _insertMention(user),
      child: SizedBox(
        height: _suggestionRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: ClipOval(
                  child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                      ? Image.network(
                          user.avatarUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => AvatarFallback(name: user.userName, size: 32),
                        )
                      : AvatarFallback(name: user.userName, size: 32),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '@${user.userName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsPanel() {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: _panelHeight,
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: _suggestions.length,
          itemExtent: _suggestionRowHeight,
          itemBuilder: (context, index) => _buildSuggestionTile(_suggestions[index]),
        ),
      ),
    );
  }

  Widget _buildOverlaySuggestions() {
    final panelWidth = _anchorWidth;
    if (panelWidth == null || panelWidth <= 0 || _suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      offset: const Offset(0, -8),
      child: UnconstrainedBox(
        alignment: Alignment.bottomLeft,
        constrainedAxis: Axis.horizontal,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: panelWidth,
          height: _panelHeight,
          child: _buildSuggestionsPanel(),
        ),
      ),
    );
  }

  Color get _accentColor => widget.accentColor ?? AppColors.primary;

  bool get _useCollapsedDecoration =>
      widget.dense && (widget.collapseDecoration || widget.maxLines == 1);

  InputDecoration _fieldDecoration() {
    return InputDecoration(
      isDense: widget.dense,
      visualDensity: widget.dense ? VisualDensity.compact : VisualDensity.standard,
      isCollapsed: _useCollapsedDecoration,
      hintText: widget.hintText,
      hintStyle: GoogleFonts.plusJakartaSans(
        color: AppColors.textMuted,
        fontSize: _baseTextStyle.fontSize ?? 14,
        height: _baseTextStyle.height,
      ),
      border: widget.filled ? null : InputBorder.none,
      enabledBorder: widget.filled ? null : InputBorder.none,
      focusedBorder: widget.filled
          ? OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: _accentColor, width: 1.5),
            )
          : InputBorder.none,
      filled: widget.filled,
      fillColor: widget.filled ? AppColors.surfaceMuted : null,
      contentPadding: _contentPadding,
    );
  }

  Widget _buildPlainTextField({Color? textColor}) {
    final isMultiline = widget.maxLines > 1;

    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      style: _baseTextStyle.copyWith(color: textColor ?? AppColors.textPrimary),
      cursorColor: _accentColor,
      keyboardType: isMultiline ? TextInputType.multiline : TextInputType.text,
      textInputAction: isMultiline ? TextInputAction.newline : TextInputAction.done,
      textAlignVertical: widget.textAlignVertical ??
          (widget.dense && widget.maxLines == 1
              ? TextAlignVertical.center
              : TextAlignVertical.top),
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      decoration: _fieldDecoration(),
    );
  }

  Widget _buildStyledTextField() {
    if (widget.maxLines > 1) {
      return _buildPlainTextField();
    }

    final padding = _contentPadding.resolve(Directionality.of(context));

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.topLeft,
          children: [
            IgnorePointer(
              child: Padding(
                padding: padding,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: Text.rich(
                    CommentMentions.buildComposerTextSpan(
                      text: widget.controller.text,
                      mentions: List.unmodifiable(_confirmedMentions),
                      baseStyle: _baseTextStyle,
                    ),
                    softWrap: true,
                  ),
                ),
              ),
            ),
            _buildPlainTextField(textColor: Colors.transparent),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleAnchorMeasure();

    final styledField = _buildStyledTextField();
    return CompositedTransformTarget(
      link: _layerLink,
      child: KeyedSubtree(
        key: _anchorKey,
        child: widget.surroundBuilder?.call(styledField) ?? styledField,
      ),
    );
  }
}
