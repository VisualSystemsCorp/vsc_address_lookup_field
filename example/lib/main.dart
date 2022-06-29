import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vsc_address_lookup_field/vsc_address_lookup_field.dart';
import 'package:google_place/google_place.dart';

void main() async {
  await dotenv.load(fileName: '.env');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Address Lookup Field Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          counterStyle: TextStyle(),
        ),
      ),
      home: const MyHomePage(title: 'Address Lookup Field Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

const _hgap = SizedBox(width: 10);
const _vgap = SizedBox(height: 10);

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _postalCodeController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  late final GooglePlace _googlePlace = GooglePlace(
    dotenv.get('API_KEY'),
    proxyUrl: dotenv.maybeGet('PROXY_URL'),
  );

  @override
  void dispose() {
    super.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            VscAddressLookupField(
              initialValue: '701 N 1st Ave',
              onSelected: _onSelected,
              onMapRequested: _onMapRequested,
              textFieldConfiguration: TextFieldConfiguration(
                controller: _streetController,
                decoration: const InputDecoration(labelText: 'Street Address'),
              ),
              placesAutocompleteFetchFn: _googlePlace.autocomplete.get,
              placesDetailsFetchFn: _googlePlace.details.get,
              poweredByGoogleLogo: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Image.asset(
                    'assets/powered_by_google_on_white_hdpi.png',
                    height: 16,
                  ),
                ),
              ),
              debugApiCalls: true,
            ),
            _vgap,
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'City'),
                    controller: _cityController,
                  ),
                ),
                _hgap,
                Expanded(
                  flex: 1,
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'State'),
                    controller: _stateController,
                  ),
                ),
                _hgap,
                Expanded(
                  flex: 2,
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'PostalCode'),
                    controller: _postalCodeController,
                  ),
                ),
              ],
            ),
            _vgap,
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Country'),
                    controller: _countryController,
                  ),
                ),
                const Spacer(flex: 3),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onSelected(Address address) {
    // Populate the other discrete fields with the selected information
    _cityController.text = address.city ?? '';
    _stateController.text = address.state ?? '';
    _postalCodeController.text = address.postalCode ?? '';
    _countryController.text = address.countryCode ?? '';
  }

  void _onMapRequested() async {
    final url = VscAddressLookupField.createGoogleMapsUrl(
      streetAddress: _streetController.text,
      city: _cityController.text,
      stateOrProvince: _stateController.text,
      postalCode: _postalCodeController.text,
      countryCode: _countryController.text,
    );

    debugPrint(url.toString());
    if (!await launchUrl(url)) {
      debugPrint('Failed to launch URL $url');
    }
  }
}
