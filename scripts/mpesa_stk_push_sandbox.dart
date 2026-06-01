import 'dart:convert';

import 'package:http/http.dart' as http;

String consumerKey = 'KAT0fSSkv24HA2v1vJQHlNbLN3uY15zspVz0ZAq68HA5B50X';
String consumerSecret =
    'TvopOs1TsY7osJm9nfDxSAB4EByhdDa5xDH52oFMxNuxaAA3S1dJkA74NQxaoq86';
String testPhoneNumber = '254708374149';

const String businessShortCode = '174379';
const String sandboxPasskey =
    'bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919';
const String callbackUrl = 'https://mydomain.com/callback';
const int amount = 1;

String _timestampNow() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}';
}

Future<String?> _fetchAccessToken() async {
  final basicAuth = base64Encode(utf8.encode('$consumerKey:$consumerSecret'));
  final response = await http.get(
    Uri.parse(
      'https://sandbox.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials',
    ),
    headers: {
      'Authorization': 'Basic $basicAuth',
      'User-Agent': 'curl/7.81.0',
      'Accept': 'application/json',
    },
  );

  if (response.statusCode != 200) {
    print(
        'Failed to fetch OAuth token (${response.statusCode}): ${response.body}');
    return null;
  }

  final body = jsonDecode(response.body) as Map<String, dynamic>;
  return body['access_token'] as String?;
}

Future<void> main() async {
  print('Requesting OAuth access token...');
  final accessToken = await _fetchAccessToken();

  if (accessToken == null || accessToken.isEmpty) {
    print('Failure: OAuth access token could not be generated.');
    return;
  }

  final timestamp = _timestampNow();
  final password = base64Encode(
    utf8.encode('$businessShortCode$sandboxPasskey$timestamp'),
  );

  final payload = <String, dynamic>{
    'BusinessShortCode': businessShortCode,
    'Password': password,
    'Timestamp': timestamp,
    'TransactionType': 'CustomerPayBillOnline',
    'Amount': amount,
    'PartyA': testPhoneNumber,
    'PartyB': businessShortCode,
    'PhoneNumber': testPhoneNumber,
    'CallBackURL': callbackUrl,
    'AccountReference': 'AeroRide Test',
    'TransactionDesc': 'AeroRide sandbox STK test',
  };

  print('Sending STK Push request...');
  final response = await http.post(
    Uri.parse(
        'https://sandbox.safaricom.co.ke/mpesa/stkpush/v1/processrequest'),
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
    body: jsonEncode(payload),
  );

  if (response.statusCode >= 200 && response.statusCode < 300) {
    print('Success: STK Push request sent successfully.');
    print(response.body);
  } else {
    print('Failure: STK Push request failed (${response.statusCode}).');
    print(response.body);
  }
}
