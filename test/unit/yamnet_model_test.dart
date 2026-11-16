import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Song radio needs the YAMNet embedding, which the stock model doesn't output:
/// tool/yamnet_add_embedding_output.py adds it. A model swapped back to the stock file would
/// still analyze — just with no radio — so this checks the file itself.
void main() {
  test('yamnet.tflite outputs the class scores and the 1024-number embedding', () {
    final model = _TfliteModel(File('android/app/src/main/assets/yamnet.tflite').readAsBytesSync());
    final outputs = model.outputs();

    expect(outputs, hasLength(2));
    expect(outputs[0].name, endsWith('final_output'));
    expect(outputs[0].shape.last, 521);
    expect(outputs[1].name, endsWith('layer28/reduce_mean'));
    expect(outputs[1].shape.last, 1024);
  });
}

/// Just enough of the TFLite flatbuffer (schema.fbs) to read the main graph's outputs.
class _TfliteModel {
  _TfliteModel(Uint8List bytes) : _b = ByteData.sublistView(bytes);
  final ByteData _b;

  int _u32(int at) => _b.getUint32(at, Endian.little);

  /// Where field [index] of the table at [table] is; null when it isn't set.
  int? _field(int table, int index) {
    final vtable = table - _b.getInt32(table, Endian.little);
    final slot = 4 + index * 2;
    if (slot >= _b.getUint16(vtable, Endian.little)) return null;
    final offset = _b.getUint16(vtable + slot, Endian.little);
    return offset == 0 ? null : table + offset;
  }

  int _ref(int at) => at + _u32(at);

  /// The table / vector / string a field points to.
  int _deref(int table, int index) => _ref(_field(table, index)!);

  List<int> _vector(int at, {required int width}) =>
      [for (var i = 0; i < _u32(at); i++) at + 4 + i * width];

  List<({String name, List<int> shape})> outputs() {
    final root = _ref(0);
    final graph = _ref(_vector(_deref(root, 2), width: 4).first); // Model.subgraphs[0]
    final tensors = _vector(_deref(graph, 0), width: 4); // SubGraph.tensors
    return [
      for (final o in _vector(_deref(graph, 2), width: 4)) // SubGraph.outputs
        _tensor(_ref(tensors[_b.getInt32(o, Endian.little)])),
    ];
  }

  ({String name, List<int> shape}) _tensor(int t) {
    final name = _deref(t, 3); // Tensor.name
    final shape = _vector(_deref(t, 0), width: 4); // Tensor.shape
    return (
      name: utf8.decode(Uint8List.sublistView(_b, name + 4, name + 4 + _u32(name))),
      shape: [for (final s in shape) _b.getInt32(s, Endian.little)],
    );
  }
}
