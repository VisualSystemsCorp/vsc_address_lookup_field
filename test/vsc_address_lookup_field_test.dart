import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:vsc_address_lookup_field/src/address_field.dart';

@GenerateMocks([
  HttpClient,
  HttpClientRequest,
  HttpClientResponse,
  HttpHeaders,
])
import 'vsc_address_lookup_field_test.mocks.dart';

const label = 'label';
final fieldFinder = find.byType(VscAddressLookupField);
final labelFinder =
    find.descendant(of: fieldFinder, matching: find.text(label));
final mapsIconFinder =
    find.descendant(of: fieldFinder, matching: find.byIcon(Icons.place));
final textFieldFinder =
    find.descendant(of: fieldFinder, matching: find.byType(TextField));
final autocompletePopupFinder = find.byKey(autocompleteOptionsKey);
final logoKey = UniqueKey();
final focusButtonKey = UniqueKey();
final focusButtonFinder = find.byKey(focusButtonKey);
final mockHttpClient = MockHttpClient();
final onSelectedAddresses = <Address>[];

void main() {
  // TODO -
  //  - no map icon

  setUp(() {
    onSelectedAddresses.clear();
    HttpOverrides.global = MockHttpOverrides();

    when(mockHttpClient.openUrl(any, any)).thenAnswer((invocation) {
      final url = invocation.positionalArguments[1] as Uri;
      final body = url.path.contains('/details/')
          ? detailsResponseBody
          : autocompleteResponseBody;
      final request = MockHttpClientRequest();
      final response = MockHttpClientResponse();
      when(request.close()).thenAnswer((_) => Future.value(response));
      when(request.addStream(any)).thenAnswer((_) async => null);
      when(response.headers).thenReturn(MockHttpHeaders());
      when(response.handleError(any, test: anyNamed('test')))
          .thenAnswer((_) => Stream.value(body));
      when(response.statusCode).thenReturn(200);
      when(response.reasonPhrase).thenReturn('OK');
      when(response.contentLength).thenReturn(body.length);
      when(response.isRedirect).thenReturn(false);
      when(response.persistentConnection).thenReturn(false);
      return Future.value(request);
    });
  });

  testWidgets('displays properly', (tester) async {
    await tester.pumpField();

    expect(labelFinder, findsOneWidget);
    expect(mapsIconFinder, findsOneWidget);
    expect(autocompletePopupFinder, findsNothing);

    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/pre_focus.png'));

    await tester.showKeyboard(fieldFinder); // Focuses
    await tester.pumpAndSettle();

    // Popup should still not be visible after focusing.
    expect(autocompletePopupFinder, findsNothing);

    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/post_focus.png'));

    await tester.enterText(fieldFinder, '1600 pennsylvania ave NW');
    await tester.pumpAndSettle();

    // No popup yet because of debounce
    expect(autocompletePopupFinder, findsNothing);

    // Wait for debounce and popup.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Autocomplete popup should now be displayed
    expect(autocompletePopupFinder, findsOneWidget);

    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/post_lookup.png'));
  });

  testWidgets('calls onSelected when selection tapped', (tester) async {
    await tester.pumpField();

    await tester.showKeyboard(fieldFinder); // Focuses
    await tester.pumpAndSettle();

    await tester.enterText(fieldFinder, '1600 pennsylvania ave NW');
    // Wait for debounce and popup.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Autocomplete popup should now be displayed
    expect(autocompletePopupFinder, findsOneWidget);

    // Tap the item with 'TAPME' in the description
    await tester.tap(find.descendant(
      of: autocompletePopupFinder,
      matching: find.textContaining('TAPME'),
    ));
    await tester.pumpAndSettle();

    // Popup should be gone
    expect(autocompletePopupFinder, findsNothing);

    expect(onSelectedAddresses.length, 1);
    final addr = onSelectedAddresses[0];
    expect(addr.streetAddress, '701 N 1st Ave W');
    expect(addr.locality, 'TAPME');
    expect(addr.city, addr.locality);
    expect(addr.administrativeAreaLevel1, 'MN');
    expect(addr.state, addr.administrativeAreaLevel1);
    expect(addr.administrativeAreaLevel2, 'St Louis County');
    expect(addr.postalCode, '55806');
    expect(addr.countryCode, 'US');
  });
}

extension MoreWidgetTester on WidgetTester {
  TextField getTextField() => widget(textFieldFinder);

  Future<void> pumpField() async {
    await pumpWidgetWithHarness(VscAddressLookupField(
      textFieldConfiguration: const TextFieldConfiguration(
          decoration: InputDecoration(
        label: Text(label),
      )),
      onMapRequested: () {},
      onSelected: (address) => onSelectedAddresses.add(address),
      googlePlacesApiKey: '',
      poweredByGoogleLogo: buildLogo(),
    ));
  }

  Future<void> pumpFieldNoMapIcon() async {
    await pumpWidgetWithHarness(
      VscAddressLookupField(
        textFieldConfiguration: const TextFieldConfiguration(
            decoration: InputDecoration(
          label: Text(label),
        )),
        onSelected: (address) {},
        googlePlacesApiKey: '',
        poweredByGoogleLogo: buildLogo(),
      ),
    );
  }

  Widget buildLogo() {
    // return  SizedBox.shrink(key: logoKey);
    return Align(
      key: logoKey,
      alignment: Alignment.centerRight,
      child: const Icon(Icons.logo_dev),
    );
  }

  Future<void> pumpWidgetWithHarness(Widget child) async {
    await pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en', 'US'),
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              // A button to test focus
              ElevatedButton(
                  key: focusButtonKey,
                  onPressed: () {},
                  child: const Text('Focus here')),
            ],
          ),
        ),
      ),
    );
    await pumpAndSettle();
  }
}

class MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return mockHttpClient;
  }
}

// https://maps.googleapis.com/maps/api/place/autocomplete/json?input=701+N+1st+Ave&key=...&sessionToken=...
final autocompleteResponseBody = utf8.encode(jsonEncode({
  "predictions": [
    {
      "description": "701 North 1st Avenue, Minneapolis, MN, USA",
      "matched_substrings": [
        {"length": 3, "offset": 0},
        {"length": 16, "offset": 4}
      ],
      "place_id": "ChIJP6i4fJEys1IRRmLjyUJ78MI",
      "reference": "ChIJP6i4fJEys1IRRmLjyUJ78MI",
      "structured_formatting": {
        "main_text": "701 North 1st Avenue",
        "main_text_matched_substrings": [
          {"length": 3, "offset": 0},
          {"length": 16, "offset": 4}
        ],
        "secondary_text": "Minneapolis, MN, USA"
      },
      "terms": [
        {"offset": 0, "value": "701"},
        {"offset": 4, "value": "North 1st Avenue"},
        {"offset": 22, "value": "Minneapolis"},
        {"offset": 35, "value": "MN"},
        {"offset": 39, "value": "USA"}
      ],
      "types": ["street_address", "geocode"]
    },
    {
      "description": "701 North 1st Avenue West, TAPME, MN, USA",
      "matched_substrings": [
        {"length": 25, "offset": 0}
      ],
      "place_id":
          "Eio3MDEgTm9ydGggMXN0IEF2ZW51ZSBXZXN0LCBEdWx1dGgsIE1OLCBVU0EiURJPCjQKMgnFJ8NWo1KuUhGSHHy9aRL46RoeCxDuwe6hARoUChIJtd3W0XNNrlIRvv5uI2vzTAcMEL0FKhQKEgnvGaisvVKuUhHxN4V9qAD4IA",
      "reference":
          "Eio3MDEgTm9ydGggMXN0IEF2ZW51ZSBXZXN0LCBEdWx1dGgsIE1OLCBVU0EiURJPCjQKMgnFJ8NWo1KuUhGSHHy9aRL46RoeCxDuwe6hARoUChIJtd3W0XNNrlIRvv5uI2vzTAcMEL0FKhQKEgnvGaisvVKuUhHxN4V9qAD4IA",
      "structured_formatting": {
        "main_text": "701 North 1st Avenue West",
        "main_text_matched_substrings": [
          {"length": 25, "offset": 0}
        ],
        "secondary_text": "Duluth, MN, USA"
      },
      "terms": [
        {"offset": 0, "value": "701 North 1st Avenue West"},
        {"offset": 27, "value": "Duluth"},
        {"offset": 35, "value": "MN"},
        {"offset": 39, "value": "USA"}
      ],
      "types": ["street_address", "geocode"]
    },
    {
      "description": "701 North 1st Avenue, Arcadia, CA, USA",
      "matched_substrings": [
        {"length": 3, "offset": 0},
        {"length": 16, "offset": 4}
      ],
      "place_id": "ChIJb6BE3eXbwoARZGWygCYX1m8",
      "reference": "ChIJb6BE3eXbwoARZGWygCYX1m8",
      "structured_formatting": {
        "main_text": "701 North 1st Avenue",
        "main_text_matched_substrings": [
          {"length": 3, "offset": 0},
          {"length": 16, "offset": 4}
        ],
        "secondary_text": "Arcadia, CA, USA"
      },
      "terms": [
        {"offset": 0, "value": "701"},
        {"offset": 4, "value": "North 1st Avenue"},
        {"offset": 22, "value": "Arcadia"},
        {"offset": 31, "value": "CA"},
        {"offset": 35, "value": "USA"}
      ],
      "types": ["premise", "geocode"]
    },
    {
      "description": "701 North 1st Avenue, Durant, OK, USA",
      "matched_substrings": [
        {"length": 3, "offset": 0},
        {"length": 16, "offset": 4}
      ],
      "place_id": "ChIJl6SWZ9BfS4YR1Y9Y4F_NKtA",
      "reference": "ChIJl6SWZ9BfS4YR1Y9Y4F_NKtA",
      "structured_formatting": {
        "main_text": "701 North 1st Avenue",
        "main_text_matched_substrings": [
          {"length": 3, "offset": 0},
          {"length": 16, "offset": 4}
        ],
        "secondary_text": "Durant, OK, USA"
      },
      "terms": [
        {"offset": 0, "value": "701"},
        {"offset": 4, "value": "North 1st Avenue"},
        {"offset": 22, "value": "Durant"},
        {"offset": 30, "value": "OK"},
        {"offset": 34, "value": "USA"}
      ],
      "types": ["premise", "geocode"]
    },
    {
      "description": "701 North 1st Avenue East, Duluth, MN, USA",
      "matched_substrings": [
        {"length": 25, "offset": 0}
      ],
      "place_id":
          "Eio3MDEgTm9ydGggMXN0IEF2ZW51ZSBFYXN0LCBEdWx1dGgsIE1OLCBVU0EiURJPCjQKMgl_W2qgu1KuUhHxeFXiEexEnhoeCxDuwe6hARoUChIJd5APPbZSrlIRxnOElBA5Mz0MEL0FKhQKEglHlquau1KuUhGNnD_uMDYNaQ",
      "reference":
          "Eio3MDEgTm9ydGggMXN0IEF2ZW51ZSBFYXN0LCBEdWx1dGgsIE1OLCBVU0EiURJPCjQKMgl_W2qgu1KuUhHxeFXiEexEnhoeCxDuwe6hARoUChIJd5APPbZSrlIRxnOElBA5Mz0MEL0FKhQKEglHlquau1KuUhGNnD_uMDYNaQ",
      "structured_formatting": {
        "main_text": "701 North 1st Avenue East",
        "main_text_matched_substrings": [
          {"length": 25, "offset": 0}
        ],
        "secondary_text": "Duluth, MN, USA"
      },
      "terms": [
        {"offset": 0, "value": "701 North 1st Avenue East"},
        {"offset": 27, "value": "Duluth"},
        {"offset": 35, "value": "MN"},
        {"offset": 39, "value": "USA"}
      ],
      "types": ["street_address", "geocode"]
    }
  ],
  "status": "OK"
}));

// https://maps.googleapis.com/maps/api/place/details/json?place_id=...
final detailsResponseBody = utf8.encode(jsonEncode({
  "html_attributions": [],
  "result": {
    "address_components": [
      {
        "long_name": "701",
        "short_name": "701",
        "types": ["street_number"]
      },
      {
        "long_name": "North 1st Avenue West",
        "short_name": "N 1st Ave W",
        "types": ["route"]
      },
      {
        "long_name": "Observation Hill",
        "short_name": "Observation Hill",
        "types": ["neighborhood", "political"]
      },
      {
        "long_name": "TAPME",
        "short_name": "TAPME",
        "types": ["locality", "political"]
      },
      {
        "long_name": "St. Louis County",
        "short_name": "St Louis County",
        "types": ["administrative_area_level_2", "political"]
      },
      {
        "long_name": "Minnesota",
        "short_name": "MN",
        "types": ["administrative_area_level_1", "political"]
      },
      {
        "long_name": "United States",
        "short_name": "US",
        "types": ["country", "political"]
      },
      {
        "long_name": "55806",
        "short_name": "55806",
        "types": ["postal_code"]
      }
    ],
    "url":
        "https://maps.google.com/?q=701+N+1st+Ave+W,+Duluth,+MN+55806,+USA&ftid=0x52ae52a356c327c5:0xd7b6150c5de6743f"
  },
  "status": "OK"
}));
