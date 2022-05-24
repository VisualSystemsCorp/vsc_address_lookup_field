import 'package:vsc_address_lookup_field/vsc_address_lookup_field.dart';

void main(List<String> args) async {
  final apikey = args[0];

  final search = MapBoxSearch(apiKey: apikey, country: 'US,CA');
  final results = await search.search('15004 Willa');
  print(results);
}
