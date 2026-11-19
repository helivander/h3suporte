import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_chatgpt_utils.dart';

const kAiProviderGemini = 'gemini';
const kAiOptionGeminiKey = 'ai-agent-gemini-key';
const kAiOptionGeminiModel = 'ai-agent-gemini-model';
const kAiDefaultGeminiModel = 'gemini-2.5-pro';
const kGeminiBase = 'https://generativelanguage.googleapis.com/v1beta';

/// Modelos sugeridos (do mais indicado para o mais simples) enquanto a lista do provedor não é carregada.
const kAiSuggestedModels = {
  'claude': ['claude-fable-5-2', 'claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5'],
  'chatgpt': ['gpt-6.1-sol', 'gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna'],
  'gemini': [
    'gemini-3.8-flash',
    'gemini-3.1-pro-preview',
    'gemini-3-flash-preview',
    'gemini-2.5-pro',
    'gemini-2.5-flash',
  ],
};

/// Deixa na lista só os modelos de texto que servem ao agente: o Gemini devolve também imagem, voz, embeddings e
/// modelos abertos. Os mais novos vêm primeiro.
List<String> filtrarModelosAi(String provider, List<String> ids) {
  if (provider != 'gemini') return ids;
  final fora = RegExp(r'tts|image|embed|live|audio|robotics|computer-use|learnlm|aqa|veo|imagen|gemma|native');
  final r = ids.where((m) => m.startsWith('gemini-') && !fora.hasMatch(m)).toSet().toList();
  int ordem(String m) {
    final v = RegExp(r'gemini-(\d+)(?:\.(\d+))?').firstMatch(m);
    return v == null ? 0 : int.parse(v[1]!) * 100 + int.parse(v[2] ?? '0');
  }

  r.sort((a, b) {
    final c = ordem(b).compareTo(ordem(a));
    return c != 0 ? c : a.compareTo(b);
  });
  return r;
}

/// Busca os modelos disponíveis no provedor. Lança uma mensagem curta em caso de erro.
Future<List<String>> fetchAiModels(String provider,
    {String apiKey = '', String baseUrl = 'https://api.anthropic.com'}) async {
  if (provider == 'chatgpt') return kAiSuggestedModels['chatgpt']!;
  if (apiKey.trim().isEmpty) throw 'Informe a chave da API para carregar a lista.';
  final http.Response r;
  if (provider == 'gemini') {
    r = await http.get(Uri.parse('$kGeminiBase/models?pageSize=200'),
        headers: {'x-goog-api-key': apiKey.trim()}).timeout(const Duration(seconds: 20));
  } else {
    r = await http.get(
        Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/models?limit=100'),
        headers: {
          'x-api-key': apiKey.trim(),
          'anthropic-version': '2023-06-01',
        }).timeout(const Duration(seconds: 20));
  }
  if (r.statusCode != 200) throw 'HTTP ${r.statusCode}: verifique a chave da API.';
  final j = jsonDecode(utf8.decode(r.bodyBytes));
  final ids = <String>[];
  if (provider == 'gemini') {
    for (final m in (j['models'] as List? ?? [])) {
      final metodos = (m['supportedGenerationMethods'] as List?) ?? [];
      if (!metodos.contains('generateContent')) continue;
      ids.add(m['name'].toString().replaceFirst('models/', ''));
    }
  } else {
    for (final m in (j['data'] as List? ?? [])) {
      ids.add(m['id'].toString());
    }
  }
  final lista = filtrarModelosAi(provider, ids);
  if (lista.isEmpty) throw 'Nenhum modelo retornado.';
  return lista;
}

dynamic _limpaSchema(dynamic v) {
  if (v is Map) {
    return {
      for (final e in v.entries)
        if (e.key != 'additionalProperties' && e.key != 'strict')
          e.key: _limpaSchema(e.value)
    };
  }
  if (v is List) return v.map(_limpaSchema).toList();
  return v;
}

/// Converte as ferramentas de função (formato Responses) para as declarações do Gemini.
List<Map<String, dynamic>> geminiTools() => [
      {
        'functionDeclarations': [
          for (final t in kChatGptComputerTools)
            {
              'name': t['name'],
              'description': t['description'],
              if (((t['parameters'] as Map?)?['properties'] as Map?)?.isNotEmpty ??
                  false)
                'parameters': _limpaSchema(t['parameters']),
            }
        ]
      }
    ];
