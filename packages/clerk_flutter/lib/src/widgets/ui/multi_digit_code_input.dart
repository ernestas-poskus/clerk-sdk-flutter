import 'package:clerk_flutter/src/widgets/control/clerk_auth.dart';
import 'package:clerk_flutter/src/widgets/ui/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Typedef for function that will verify input
typedef InputVerifier = Future<bool> Function(String);

/// A widget which takes a multiple-digit OTC code
///
class MultiDigitCodeInput extends StatefulWidget {
  /// Construct a [MultiDigitCodeInput]
  const MultiDigitCodeInput({
    super.key,
    required this.onSubmit,
    this.length = 6,
    this.isSmall = false,
    this.focusNode,
    this.code = '',
  });

  /// Function to call once all digits have been entered
  final InputVerifier onSubmit;

  /// The number of digits to be entered
  final int length;

  /// Whether the widget should display in a trimmer form
  final bool isSmall;

  /// Focus node
  final FocusNode? focusNode;

  /// Kicker to update the code from outside
  final String code;

  @override
  State<MultiDigitCodeInput> createState() => _MultiDigitCodeInputState();
}

class _MultiDigitCodeInputState extends State<MultiDigitCodeInput>
    with TextInputClient
    implements AutofillClient {
  late TextEditingValue _editingValue;
  late FocusNode _focusNode;
  TextInputConnection? _connection;
  AutofillGroupState? _currentAutofillScope;
  OverlayEntry? _contextMenuEntry;

  bool loading = false;

  bool get _hasInputConnection => _connection?.attached ?? false;

  @override
  TextEditingValue? get currentTextEditingValue => _editingValue;

  @override
  AutofillScope? get currentAutofillScope => _currentAutofillScope;

  @override
  String get autofillId => 'NumberInput-$hashCode';

  @override
  TextInputConfiguration get textInputConfiguration {
    return TextInputConfiguration(
      autofillConfiguration: AutofillConfiguration(
        uniqueIdentifier: autofillId,
        autofillHints: const [AutofillHints.oneTimeCode],
        currentEditingValue: _editingValue,
      ),
      inputType: TextInputType.number,
      inputAction: TextInputAction.go,
      autocorrect: false,
    );
  }

  @override
  void initState() {
    super.initState();
    _editingValue = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
      composing: TextRange(start: 0, end: 0),
    );
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => requestKeyboard());
    HardwareKeyboard.instance.addHandler(_onHwKeyChanged);
  }

  bool _onHwKeyChanged(KeyEvent event) {
    if (event case KeyUpEvent event
        when event.logicalKey == LogicalKeyboardKey.backspace) {
      final text = _editingValue.text;
      if (text.isNotEmpty) {
        final newEditingValue = TextEditingValue(
          text: text.substring(0, text.length - 1),
          selection: TextSelection.collapsed(offset: text.length - 1),
        );
        _connection?.setEditingState(newEditingValue);
        setState(() => _editingValue = newEditingValue);
        return true;
      }
    }
    return false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final AutofillGroupState? newAutofillGroup = AutofillGroup.maybeOf(context);
    if (currentAutofillScope != newAutofillGroup) {
      _currentAutofillScope?.unregister(autofillId);
      _currentAutofillScope = newAutofillGroup;
      _currentAutofillScope?.register(this);
    }
  }

  @override
  void didUpdateWidget(covariant MultiDigitCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final code = widget.code;
    if (oldWidget.code != code && code != _editingValue.text) {
      _editingValue = TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length - 1),
      );
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _openInputConnection();
    } else {
      _closeInputConnectionIfNeeded();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _hideContextMenu();
    HardwareKeyboard.instance.removeHandler(_onHwKeyChanged);
    _currentAutofillScope?.unregister(autofillId);
    if (widget.focusNode == null) {
      // must be one we've created locally, so dispose of it now
      _focusNode.dispose();
    }
    _closeInputConnectionIfNeeded();
    super.dispose();
  }

  @override
  void autofill(TextEditingValue newEditingValue) {
    _handleNewInput(newEditingValue.text);
  }

  void _handleNewInput(String input) {
    final digitsOnly = input.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) return;

    final code = digitsOnly.length > widget.length
        ? digitsOnly.substring(0, widget.length)
        : digitsOnly;

    updateEditingValue(
      TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      _handleNewInput(text);
    }
  }

  void _showContextMenu(Offset globalPosition) {
    _hideContextMenu();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _contextMenuEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideContextMenu,
            ),
          ),
          AdaptiveTextSelectionToolbar.buttonItems(
            anchors: TextSelectionToolbarAnchors(primaryAnchor: globalPosition),
            buttonItems: [
              ContextMenuButtonItem(
                onPressed: () {
                  _hideContextMenu();
                  _pasteFromClipboard();
                },
                type: ContextMenuButtonType.paste,
              ),
            ],
          ),
        ],
      ),
    );

    overlay.insert(_contextMenuEntry!);
  }

  void _hideContextMenu() {
    _contextMenuEntry?.remove();
    _contextMenuEntry = null;
  }

  bool _hasCursor(int i) {
    if (_focusNode.hasFocus == false) return false;

    final length = _editingValue.text.length;
    if (i == length) return true;
    if (length == widget.length && i == length - 1) return true;

    return false;
  }

  String? _labelFor(int i) {
    if (loading) {
      return null;
    }

    final text = _editingValue.text;
    return i < text.length ? text[i] : null;
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        PasteTextIntent: CallbackAction<PasteTextIntent>(
          onInvoke: (intent) {
            _pasteFromClipboard();
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: _focusNode,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _hideContextMenu();
            requestKeyboard();
          },
          onLongPressStart: (details) {
            requestKeyboard();
            _showContextMenu(details.globalPosition);
          },
          onSecondaryTapUp: (details) {
            requestKeyboard();
            _showContextMenu(details.globalPosition);
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 0; i < widget.length; ++i) //
                _CodeDigit(
                  isSmall: widget.isSmall,
                  hasCursor: _hasCursor(i),
                  label: _labelFor(i),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void requestKeyboard() {
    FocusScope.of(context).requestFocus(_focusNode);
    _openInputConnection();
  }

  void _openInputConnection() {
    if (!_hasInputConnection) {
      _connection =
          _currentAutofillScope?.attach(this, textInputConfiguration) ??
              TextInput.attach(this, textInputConfiguration);
      _connection!.setEditingState(_editingValue);
    }
    _connection!.show();
  }

  void _closeInputConnectionIfNeeded() {
    if (_hasInputConnection) {
      _connection!.close();
      _connection = null;
    }
  }

  @override
  void performAction(TextInputAction action) {
    _focusNode.unfocus();
  }

  @override
  Future<void> updateEditingValue(TextEditingValue value) async {
    setState(() => _editingValue = value);
    if (value.text.length == widget.length) {
      setState(() => loading = true);
      final succeeded = await widget.onSubmit(value.text);
      if (context.mounted) {
        _focusNode.nextFocus();
        if (succeeded == false) {
          _editingValue = const TextEditingValue(
            text: '',
            selection: TextSelection.collapsed(offset: 0),
          );
          requestKeyboard();
        }
        setState(() => loading = false);
      }
    }
    if (context.mounted) {
      _openInputConnection();
      setState(() => _connection!.setEditingState(_editingValue));
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    // Not required
  }

  @override
  void connectionClosed() {
    // Not required
  }

  @override
  void didChangeInputControl(
      TextInputControl? oldControl, TextInputControl? newControl) {
    // Not required
  }

  @override
  void insertContent(KeyboardInsertedContent content) {
    // Not required
  }

  @override
  void insertTextPlaceholder(Size size) {
    // Not required
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    // Not required
  }

  @override
  void performSelector(String selectorName) {
    // Not required
  }

  @override
  void removeTextPlaceholder() {
    // Not required
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    // Not required
  }

  @override
  void showToolbar() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final position = renderBox.localToGlobal(
        Offset(renderBox.size.width / 2, 0),
      );
      _showContextMenu(position);
    }
  }
}

class _PulsingCursor extends StatefulWidget {
  const _PulsingCursor({required this.height});

  final double height;

  @override
  State<_PulsingCursor> createState() => _PulsingCursorState();
}

class _PulsingCursorState extends State<_PulsingCursor>
    with SingleTickerProviderStateMixin {
  static const _cycleDuration = Duration(milliseconds: 1200);

  void _update() {
    if (mounted) {
      setState(() {});
    }
  }

  late final _controller =
      AnimationController(duration: _cycleDuration, vsync: this)
        ..repeat(period: _cycleDuration, reverse: true)
        ..addListener(_update);
  late final _curve =
      CurvedAnimation(parent: _controller, curve: Curves.decelerate);

  @override
  void dispose() {
    _controller.removeListener(_update);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.bottomCenter,
      child: Padding(
        padding: allPadding4,
        child: SizedBox(
          width: double.infinity,
          height: widget.height,
          child: ColoredBox(
            color: Colors.black.withValues(alpha: _curve.value * 0.5),
          ),
        ),
      ),
    );
  }
}

class _CodeDigit extends StatelessWidget {
  const _CodeDigit({
    required this.isSmall,
    required this.hasCursor,
    this.label,
  });

  final bool isSmall;
  final bool hasCursor;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final themeExtension = ClerkAuth.themeExtensionOf(context);
    final decoration = BoxDecoration(
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      border: Border.fromBorderSide(
        BorderSide(color: themeExtension.colors.borderSide),
      ),
    );
    final textStyle = TextStyle(
      color: themeExtension.colors.lightweightText,
      fontWeight: FontWeight.bold,
    );

    final children = [
      if (label case String label) //
        Align(child: Text(label, style: textStyle)),
      if (hasCursor) //
        _PulsingCursor(height: isSmall ? 1.0 : 2.0),
    ];

    return DecoratedBox(
      decoration: decoration,
      child: SizedBox.square(
        dimension: isSmall ? 18.0 : 38.0,
        child: switch (children.length) {
          2 => Stack(children: children),
          1 => children.first,
          _ => null,
        },
      ),
    );
  }
}
