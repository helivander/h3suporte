import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart' show kH3Central;
import 'package:flutter_hbb/desktop/pages/h3_home_layout.dart' show H3Cores;
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:url_launcher/url_launcher.dart';

/// Planos do H3 Suporte na vitrine da Central. Depois do pagamento confirmado, a
/// própria página oferece "Baixar o agente".
const kH3AssinarUrl = '$kH3Central/servicos/h3suporte#comprar';

const _kOpcaoFechada = 'h3-oferta-agente-fechada';

/// Cliente (só recebe acesso): oferece assinar para também acessar outros
/// computadores com o agente. Fechado uma vez, não volta neste computador.
class H3OfertaAgente extends StatefulWidget {
  final VoidCallback? onFechar;
  const H3OfertaAgente({super.key, this.onFechar});

  @override
  State<H3OfertaAgente> createState() => _H3OfertaAgenteState();
}

class _H3OfertaAgenteState extends State<H3OfertaAgente> {
  bool _fechada = bind.mainGetLocalOption(key: _kOpcaoFechada) == 'Y';

  Future<void> _fechar() async {
    setState(() => _fechada = true);
    await bind.mainSetLocalOption(key: _kOpcaoFechada, value: 'Y');
    widget.onFechar?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_fechada) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 14),
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
              IconButton(
                tooltip: 'Fechar',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: _fechar,
                icon: Icon(Icons.close_rounded, color: H3Cores.apagado),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
            ),
          ],
        ),
      ),
    );
  }
}
