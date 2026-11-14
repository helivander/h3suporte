import 'package:flutter_hbb/models/ai_chatgpt_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PKCE challenge is unpadded base64url SHA-256 of the verifier', () {
    // Expected value computed with Node's crypto module.
    expect(chatGptPkceChallenge('h3-suporte-pkce-verifier-0123456789abcdefghijklmn'),
        'oO9au67bINSAzSwsMJybwQE9HkH5DN1C6QiHl1JEjoI');
  });

  test('first login registers the app; later logins reuse the client id', () {
    Uri url(String? clientId) => chatGptAuthorizeUrl(
        clientId: clientId,
        hostId: 'urn:uuid:00000000-0000-4000-8000-000000000000',
        redirectUri: 'http://127.0.0.1:1455/auth/callback',
        state: 's',
        nonce: 'n',
        codeChallenge: 'c');
    final first = url(null).queryParameters;
    expect(first['client_id'], 'dynamic_agent_client');
    expect(first['agent_name_hint'], kChatGptAppName);
    expect(first['scope'], contains('chatgpt.tokens.use.direct'));
    expect(first['code_challenge_method'], 'S256');

    final again = url('oaiapp_x').queryParameters;
    expect(again['client_id'], 'oaiapp_x');
    expect(again.containsKey('agent_name_hint'), isFalse);
  });

  test('stream parsing returns the completed response or the error code', () {
    expect(
        parseChatGptStream('event: response.created\n'
            'data: {"type":"response.created"}\n\n'
            'data: {"type":"response.completed","response":{"output":[]}}\n'),
        {'output': []});
    expect(
        () => parseChatGptStream(
            'data: {"type":"response.failed","response":{"error":'
            '{"code":"subscription_sharing_usage_limit_exceeded"}}}\n'),
        throwsA(isA<ChatGptStreamError>().having(
            (e) => e.code, 'code', 'subscription_sharing_usage_limit_exceeded')));
    expect(() => parseChatGptStream('data: {"type":"response.created"}\n'),
        throwsA(isA<ChatGptStreamError>()));
  });
}
