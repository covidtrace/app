import 'dart:math';

import 'package:flutter/material.dart';

class CodePin extends StatefulWidget {
  final int size;
  final int flex;
  final void Function(String) onChange;

  CodePin({Key key, this.size = 8, this.flex = 3, this.onChange})
      : super(key: key);

  @override
  CodePinState createState() => CodePinState();
}

class CodePinState extends State<CodePin> {
  List<TextEditingController> _controllers = [];
  List<FocusNode> _focusNodes = [];
  List<String> _values = [];

  @override
  void initState() {
    super.initState();

    createFocusAndControllers();
  }

  @override
  void dispose() {
    super.dispose();

    _focusNodes.forEach((fn) => fn.dispose());
    _controllers.forEach((c) => c.dispose());
  }

  @override
  void didUpdateWidget(oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.size != oldWidget.size) {
      createFocusAndControllers();
    }
  }

  void createFocusAndControllers() {
    List<ChangeNotifier> dispose = [..._focusNodes, ..._controllers];

    setState(() {
      var size = widget.size;
      _values = List.generate(size, (_) => '');
      _focusNodes = List.generate(size, (_) => FocusNode());
      _controllers = List.generate(size, (_) => TextEditingController());
      _controllers.asMap().forEach(
          (index, c) => c.addListener(() => onControllerChange(index)));
    });

    // TODO(wes): Make sure we dispose of existing objects
    // This is currentl causing an exception
    // dispose.forEach((item) => item.dispose());
  }

  Widget createCodeField(context, index) {
    return Theme(
      data: Theme.of(context).copyWith(textSelectionColor: Colors.transparent),
      child: TextField(
        style: Theme.of(context).textTheme.headline5,
        showCursor: false,
        enableInteractiveSelection: false,
        maxLength: 1,
        maxLengthEnforced: true,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          counterText: '',
        ),
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        onTap: () => onTap(index),
        onChanged: (value) => onChange(index, value),
      ),
    );
  }

  void onChange(int index, String value) {
    _values[index] = value;
    widget.onChange(_values.join('').trim());
  }

  void onTap(int index) {
    _controllers[index].selection = TextSelection(
        baseOffset: 0, extentOffset: _controllers[index].value.text.length);
  }

  void onControllerChange(int index) {
    var controller = _controllers[index];
    var selection = controller.selection;
    var hasFocus = _focusNodes[index].hasFocus;
    var valueChanged = controller.text != _values[index];

    // Disregard updates to fields that are losing focus
    if (!hasFocus &&
        selection.baseOffset == -1 &&
        selection.extentOffset == -1) {
      return;
    }

    // If user deleted, go back
    if (controller.text.isEmpty && valueChanged) {
      focusField(index - 1);
    } else if (valueChanged ||
        selection.baseOffset == 1 && selection.extentOffset == 1) {
      focusField(index + 1);
    }
  }

  void focusField(int index) {
    index = max(0, min(widget.size - 1, index));

    _focusNodes[index].requestFocus();
    _controllers[index].selection = TextSelection(
        baseOffset: 0, extentOffset: _controllers[index].text.length);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ...List.generate(widget.size, (index) {
            return [
              Flexible(
                flex: widget.flex,
                child: createCodeField(context, index),
              ),
              Spacer(flex: 1),
            ];
          }).expand((el) => el),
        ],
      ),
    );
  }
}
