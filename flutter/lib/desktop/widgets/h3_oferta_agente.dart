import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/h3_home_layout.dart' show H3Cores;
import 'package:url_launcher/url_launcher.dart';

/// Planos do H3 Suporte na vitrine da Central. Depois do pagamento confirmado, a
/// própria página oferece "Baixar o agente".
const kH3AssinarUrl = 'https://keys.h3info.com/servicos/h3suporte#comprar';

/// Cliente (só recebe acesso): oferece assinar para também acessar outros
/// computadores com o agente.
class H3OfertaAgente extends StatelessWidget {
  const H3OfertaAgente({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: H3Cores.painel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: H3Cores.destaque.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.screen_share_outlined,
                size: 18, color: H3Cores.destaque),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Quer acessar outros computadores?',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: H3Cores.texto)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
              'Assine o H3 Suporte no site e baixe o agente para fazer acesso remoto.',
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: H3Cores.apagado)),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: H3Cores.destaque,
              foregroundColor: H3Cores.destaqueTinta,
            ),
            onPressed: () => launchUrl(Uri.parse(kH3AssinarUrl),
                mode: LaunchMode.externalApplication),
            child: const Text('Assinar e baixar o agente'),
          ),
        ],
      ),
    );
  }
}
