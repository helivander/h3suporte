import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:url_launcher/url_launcher.dart';

/// Página de planos do H3 Suporte na Central (aumentar o plano).
const kH3PlanosUrl = '$kH3Central/servicos/h3suporte#comprar';

String _quando(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  String dois(int n) => n.toString().padLeft(2, '0');
  return 'último acesso em ${dois(d.day)}/${dois(d.month)}/${d.year}';
}

/// Limite de computadores do plano cheio no login: lista os computadores que ocupam as vagas e deixa escolher um
/// para remover (o login seguinte libera a vaga e entra) ou abrir os planos. Devolve o id escolhido ou null.
Future<String?> h3EscolherComputadorParaLiberar(H3LimiteComputadores e) {
  final liberaveis = e.ocupados.where((o) => o.podeLiberar).toList();
  String? escolhido = liberaveis.length == 1 ? liberaveis.first.id : null;
  return gFFI.dialogManager.show<String?>((setState, close, context) {
    final cores = Theme.of(context).colorScheme;
    Widget item(H3ComputadorOcupado o) {
      final detalhe = [
        if (o.conta.isNotEmpty) o.conta,
        _quando(o.ultimoAcesso),
      ].where((s) => s.isNotEmpty).join(' · ');
      return RadioListTile<String>(
        value: o.id,
        groupValue: escolhido,
        onChanged: o.podeLiberar ? (v) => setState(() => escolhido = v) : null,
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(o.nome.isEmpty ? 'Computador sem nome' : o.nome,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            o.podeLiberar
                ? detalhe
                : '$detalhe\nSó o titular da assinatura pode remover este computador.',
            style: const TextStyle(fontSize: 12)),
        isThreeLine: !o.podeLiberar,
      );
    }

    return CustomAlertDialog(
      title: const Text('Limite de computadores do plano'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.cause, style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
              if (e.ocupados.isEmpty)
                const Text(
                    'Remova um computador no portal do assinante ou aumente o plano.')
              else ...[
                Text('Computadores conectados à conta:',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cores.onSurface.withOpacity(0.7))),
                const SizedBox(height: 4),
                ...e.ocupados.map(item),
                const SizedBox(height: 8),
                Text(
                    'O computador removido sai da conta na hora e precisa entrar de novo para voltar a usá-la.',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: cores.onSurface.withOpacity(0.6))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        dialogButton('Cancelar', onPressed: () => close(null), isOutline: true),
        dialogButton('Aumentar o plano', onPressed: () {
          launchUrl(Uri.parse(kH3PlanosUrl),
              mode: LaunchMode.externalApplication);
        }, isOutline: true),
        if (liberaveis.isNotEmpty)
          dialogButton('Remover e entrar',
              onPressed: escolhido == null ? null : () => close(escolhido)),
      ],
      onCancel: () => close(null),
    );
  }, tag: 'h3-limite-computadores');
}
