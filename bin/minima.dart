import 'package:shelf_router/shelf_router.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:args/args.dart';

import 'dart:math';
import 'dart:io';

const String codeCharacters =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

String hostname = '0.0.0.0';
String domain = 'http://localhost:8080/';
int? codeLength = 6;
String filename = "urls.csv";

var rand = Random();
var app = Router();
int codesSinceSave = 0;

Map<String, Uri> urlMap = {
  '' : Uri(),
};

void main(List<String> arguments) async {
  var argParser = ArgParser();
  argParser.addOption('port', abbr: 'p');
  argParser.addOption('hostname');
  argParser.addOption('domain', abbr: 'd');
  argParser.addOption('codelen', abbr: 'l');
  argParser.addOption('dbfile', abbr: 'f');

  var args = argParser.parse(arguments);

  int? port = args['port'] ?? 8080;

  if (port == null) {
    print("Invalid port ${args['port']}");
    exitCode = 64;
    return;
  }

  codeLength = int.tryParse(args['codelen'] ?? "6");

  if (codeLength == null) {
    print('Invalid code length value ${args['codelen']}');
    exitCode = 64;
    return;
  }

  hostname = args['hostname'] ?? hostname;
  domain = args['domain'] ?? domain;
  filename = args['dbfile'] ?? filename;

  await loadCodes(filename);

  app.get('/<code>', (Request request, String code) {
    if (urlMap[code] == null) {
      print('GET - $code : Invalid');
      return Response.notFound(null);
    }

    print('GET - $code : ${urlMap[code]}');
    return Response.found(urlMap[code].toString());
  });

  app.post('/<url>', (Request request, String urlStr) {
    Uri? uri = Uri.tryParse(Uri.decodeFull(urlStr));

    if (uri == null) {
      print('POST - Malformed URL');
      return Response.badRequest(body: 'Malformed url');
    }

    String? code;

    if (urlMap.containsValue(uri)) {
      code = urlMap.keys.firstWhere((key) => urlMap[key] == uri);
      print('POST - (Reused code) $code : $uri');
      return Response.ok('$domain$code');
    }

    code = generateCode(codeLength!);

    if (code == null) {
      print('POST - (New code) Failed to generate code within 5 attempts');
      return Response.internalServerError(
          body: 'Failed to generate code within 5 attempts');
    }

    urlMap[code] = uri;

    codesSinceSave++;

    if (codesSinceSave >= 3) {
      saveCodes(filename);
      codesSinceSave = 0;
    }

    print('POST - (New code) $code : ${uri.toString()}');
    return Response.ok('$domain$code');
  });

  var server = await io.serve(app, hostname, port);
  print("Serving minima at http://${server.address.host}:${server.port}");
}

String? generateCode(int length) {
  String code = '';
  int attempts = 0;

  while (urlMap.containsKey(code) && attempts < 5) {
    code = '';

    for (int i = 0; i < length; i++) {
      code += codeCharacters[rand.nextInt(codeCharacters.length)];
    }

    attempts++;
  }

  if (attempts > 5) {
    return null;
  }

  return code;
}

Future<bool> loadCodes(String filename) async {
  print('Loading URLs from $filename');

  if (!await File(filename).exists()) {
    print('File $filename does not exist');
    return false;
  }

  final file = File(filename);

  String contents = await file.readAsString();

  for (String line in contents.split('\n')) {
    if (!line.contains(';')) {
      continue;
    }

    String code = line.split(';')[0];
    Uri? url = Uri.tryParse(Uri.decodeFull(line.split(';')[1]));

    if (url == null) {
      print('Unreadable URL for code $code');
      continue;
    }

    urlMap[code] = url;
  }

  return true;
}

Future<bool> saveCodes(String filename) async {
  print('Saving URLs to $filename');

  final file = File(filename);
  String contents = '';

  for (MapEntry<String, Uri> entry in urlMap.entries) {
    if (entry.key != '') {
      contents += '${entry.key};${Uri.encodeComponent(entry.value.toString())}\n';
    }
  }

  file.writeAsString(contents);

  return true;
}