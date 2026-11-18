import 'dart:convert';

import 'package:flutter_hbb/models/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ferramentas do Gemini têm as ações do computador e sem campos não aceitos', () {
    final decl = geminiTools().first['functionDeclarations'] as List;
    final nomes = decl.map((d) => d['name']).toList();
    expect(nomes, containsAll(['screenshot', 'left_click', 'type', 'key']));
    final texto = jsonEncode(decl);
    expect(texto.contains('additionalProperties'), isFalse);
    expect(texto.contains('"strict"'), isFalse);
    final shot = decl.firstWhere((d) => d['name'] == 'screenshot') as Map;
    expect(shot.containsKey('parameters'), isFalse);
  });
}
