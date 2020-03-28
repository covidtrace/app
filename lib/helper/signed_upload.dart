import 'dart:convert';
import 'package:http/http.dart' as http;

Future<bool> signedUpload(Map<String, dynamic> config,
    {Map<String, dynamic> query,
    Map<String, String> headers,
    String body}) async {
  var signUri = Uri.parse(config['notaryUrl']).replace(queryParameters: query);

  var signResp = await http.post(signUri);
  if (signResp.statusCode != 200) {
    print('failed to request signed URL');
    return false;
  }

  var signJson = jsonDecode(signResp.body);

  var signedUrl = signJson['signed_url'];
  if (signedUrl == null) {
    print('no signed URL in response');
    return false;
  }

  var uploadResp = await http.put(
    signedUrl,
    headers: headers,
    body: body,
  );

  if (uploadResp.statusCode != 200) {
    print('signed upload failed ${uploadResp.statusCode}');
    print(uploadResp.body);
  }

  return uploadResp.statusCode == 200;
}
