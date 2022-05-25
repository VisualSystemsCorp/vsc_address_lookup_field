import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vsc_address_lookup_field/vsc_address_lookup_field.dart';

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

class MyHomePage extends StatelessWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            VscAddressLookupField(
              googlePlacesApiKey: dotenv.get('API_KEY'),
              poweredByGoogleLogo: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Image.asset(
                  'assets/powered_by_google_on_white_hdpi.png',
                  height: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
