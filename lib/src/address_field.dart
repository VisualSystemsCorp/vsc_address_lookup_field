import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:google_place/google_place.dart';
import 'package:vsc_address_lookup_field/src/debouncer.dart';

/// A field which provides autocomplete of street address information via the
/// Google Places API.
///
/// See also:
/// - https://developers.google.com/maps/documentation/places/web-service/autocomplete
/// - https://developers.google.com/maps/documentation/places/web-service/details
/// - https://developers.google.com/maps/documentation/places/web-service/session-tokens
/// - https://developers.google.com/maps/documentation/places/web-service/policies#logo_requirements.
///
class VscAddressLookupField extends StatefulWidget {
  const VscAddressLookupField({
    Key? key,
    required this.googlePlacesApiKey,
    required this.poweredByGoogleLogo,
    required this.onSelected,
    this.onMapRequested,
    this.textFieldConfiguration = const TextFieldConfiguration(),
    this.readOnly = false,
    this.initialValue,
    this.maxOptionsWidth = 480,
    this.debounceDuration = const Duration(milliseconds: 500),
    this.debugApiCalls = false,
    this.proxyUrl,
  }) : super(key: key);

  final String googlePlacesApiKey;
  final bool readOnly;
  final String? initialValue;
  final void Function(Address) onSelected;
  final VoidCallback? onMapRequested;
  final double? maxOptionsWidth;
  final String? proxyUrl;

  /// How long to wait after a keypress before calling the Google Places Autocomplete API.
  final Duration debounceDuration;

  /// You must supply a logo for the search results. See
  /// https://developers.google.com/maps/documentation/places/web-service/policies#logo_requirements.
  final Widget poweredByGoogleLogo;

  /// The configuration of the [TextField](https://docs.flutter.io/flutter/material/TextField-class.html)
  /// that the VscAddressLookupField widget displays
  final TextFieldConfiguration textFieldConfiguration;

  final bool debugApiCalls;

  @override
  State<VscAddressLookupField> createState() => _VscAddressLookupFieldState();

  static Uri createGoogleMapsUrl({
    String? streetAddress,
    String? city,
    String? stateOrProvince,
    String? postalCode,
    String? countryCode,
  }) {
    final parts = <String>[];
    if (streetAddress != null) parts.add(streetAddress);
    if (city != null) parts.add(city);
    if (stateOrProvince != null) parts.add(stateOrProvince);
    if (postalCode != null) parts.add(postalCode);
    if (countryCode != null) parts.add(countryCode);
    final query = parts.join(',');
    return Uri.https('maps.google.com', '', {'q': query});
  }
}

class _VscAddressLookupFieldState extends State<VscAddressLookupField> {
  static const Uuid _uuid = Uuid();

  /// This is the controller that the [RawAutocomplete] field listens to. The
  /// value set in this controller is debounced from the value in [_textEditingController].
  late final TextEditingController _autocompleteTextEditingController =
      TextEditingController();

  /// This is the controller that the [TextField] actually uses. We listen to it
  /// for changes and forward the changes to [_autocompleteTextEditingController]
  /// after a debounce period.
  late final TextEditingController _textEditingController =
      widget.textFieldConfiguration.controller ?? TextEditingController();

  late final _autocompleteControllerDebouncer =
      Debouncer(_updateAutocompleteController);

  /// Track if the field is "dirty". We only perform a Places API Autocomplete call
  /// if the field has physically changed. This prevents the overlay from opening
  /// when the field has a value and just receives focus. The field is considered "dirty"
  /// if the value changed since the last Autocomplete or Details API call.
  bool _fieldIsDirty = false;
  String _lastFieldValue = '';

  late final _autocompleteFocusNode =
      widget.textFieldConfiguration.focusNode ?? FocusNode();

  late final GooglePlace _googlePlace = GooglePlace(
    widget.googlePlacesApiKey,
    proxyUrl: widget.proxyUrl,
  );
  String? _sessionToken;

  @override
  void initState() {
    super.initState();

    if (widget.initialValue != null) {
      _textEditingController.text = widget.initialValue!;
    }

    _autocompleteTextEditingController.text = _textEditingController.text;
    _lastFieldValue = _textEditingController.text;
    _fieldIsDirty = false;

    // Hook up the autocomplete controller as a delegate to the primary one.
    // Make sure to do this AFTER setting the value on _textEditingController.
    _textEditingController.addListener(_textEditingControllerListener);
    // Field should not be dirty after it loses focus.
    _autocompleteFocusNode.addListener(() {
      if (!_autocompleteFocusNode.hasFocus) {
        _resetFieldDirtyFlag();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    // Only dispose of _textEditingController if we created it.
    if (_textEditingController != widget.textFieldConfiguration.controller) {
      _textEditingController.dispose();
    }

    if (_autocompleteFocusNode != widget.textFieldConfiguration.focusNode) {
      _autocompleteFocusNode.dispose();
    }

    _autocompleteTextEditingController.dispose();
    _autocompleteControllerDebouncer.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<_AutocompleteResult>(
      focusNode: _autocompleteFocusNode,
      textEditingController: _autocompleteTextEditingController,
      displayStringForOption: (result) => result.optionString,
      optionsViewBuilder: (context, onSelected, options) {
        return _AutocompleteOptions<_AutocompleteResult>(
          displayStringForOption: (result) => result.optionString,
          onSelected: onSelected,
          options: options,
          poweredByGoogleLogo: widget.poweredByGoogleLogo,
          maxOptionsWidth: widget.maxOptionsWidth,
        );
      },
      optionsBuilder: (textEditingValue) => _search(textEditingValue.text),
      onSelected: _onSelected,
      fieldViewBuilder: _buildFieldView,
    );
  }

  void _textEditingControllerListener() {
    _autocompleteControllerDebouncer.trigger(widget.debounceDuration);
  }

  void _updateAutocompleteController() {
    _fieldIsDirty = _textEditingController.text != _lastFieldValue;
    _lastFieldValue = _textEditingController.text;
    if (_fieldIsDirty) {
      _autocompleteTextEditingController.value = _textEditingController.value;
    }
  }

  void _resetFieldDirtyFlag() {
    _fieldIsDirty = false;
    // Clear RawAutocomplete's view of the text so it recalculates an empty
    // set of values and does not display the overlay the next time focus is
    // gained.
    _autocompleteTextEditingController.text = '';
  }

  /// Search for autocomplete results.
  Future<Iterable<_AutocompleteResult>> _search(String searchString) async {
    if (searchString.trim().isEmpty || !_fieldIsDirty) {
      return const [];
    }

    _fieldIsDirty = false;
    _sessionToken ??= _uuid.v4().toString();
    if (widget.debugApiCalls) {
      debugPrint(
          'Performing Google Places Autocomplete API request. Session=$_sessionToken');
    }

    final results = await _googlePlace.autocomplete
        .get(searchString, sessionToken: _sessionToken);
    if (results == null ||
        results.status != 'OK' ||
        results.predictions == null ||
        results.predictions!.isEmpty) {
      debugPrint(
          'Google Places Autocomplete API request failed. status=${results?.status}');
      return const [];
    }

    return results.predictions!
        .map((prediction) => _AutocompleteResult(prediction));
  }

  Future<void> _onSelected(_AutocompleteResult selectedResult) async {
    final finalSessionToken = _sessionToken!;
    // Once we get the details, we have to clear the session token,
    // otherwise we'll get charged per request.
    _sessionToken = null;

    if (widget.debugApiCalls) {
      debugPrint(
          'Performing Google Places Details API request. Session=$finalSessionToken');
    }

    // Get the address components from Place Details.
    final result = await _googlePlace.details.get(
        selectedResult.prediction.placeId!,
        fields: 'address_component,url',
        sessionToken: finalSessionToken);
    if (result == null ||
        result.status != 'OK' ||
        result.result?.addressComponents == null) {
      // Failed. Don't set anything else for the field.
      debugPrint(
          'Google Places Details API request failed. status=${result?.status}');
      return;
    }

    final addressComponents = result.result!.addressComponents!;

    // Sample components:
    // 0 = {AddressComponent}
    // longName = "123"
    // shortName = "123"
    // types = {CastList} [street_number]
    // 1 = {AddressComponent}
    // longName = "Rushmore Court"
    // shortName = "Rushmore Ct"
    // types = {CastList} [route]
    // 2 = {AddressComponent}
    // longName = "Minneapolis"
    // shortName = "Minneapolis"
    // types = {CastList} [locality, political]
    // 3 = {AddressComponent}
    // longName = "Happenin County"
    // shortName = "Happenin County"
    // types = {CastList} [administrative_area_level_2, political]
    // 4 = {AddressComponent}
    // longName = "Minnesota"
    // shortName = "MN"
    // types = {CastList} [administrative_area_level_1, political]
    // 5 = {AddressComponent}
    // longName = "United States"
    // shortName = "US"
    // types = {CastList} [country, political]
    // 6 = {AddressComponent}
    // longName = "55306"
    // shortName = "55306"
    // types = {CastList} [postal_code]
    // 7 = {AddressComponent}
    // longName = "6360"
    // shortName = "6360"
    // types = {CastList} [postal_code_suffix]
    final streetNumber =
        _getAddressComponent(addressComponents, 'street_number');
    final route = _getAddressComponent(addressComponents, 'route');
    var subPremise = _getAddressComponent(addressComponents, 'subpremise');
    final locality = _getAddressComponent(addressComponents, 'locality');
    final admin1 =
        _getAddressComponent(addressComponents, 'administrative_area_level_1');
    final admin2 =
        _getAddressComponent(addressComponents, 'administrative_area_level_2');
    final country = _getAddressComponent(addressComponents, 'country');
    var postalCode = _getAddressComponent(addressComponents, 'postal_code');
    final postalCodeSuffix =
        _getAddressComponent(addressComponents, 'postal_code_suffix');

    var streetAddress =
        '${streetNumber ?? ''}${streetNumber == null ? '' : ' '}${route ?? ''}';
    if (subPremise != null) {
      // Handle "#101", "Apt 5", "Ste 232"
      // If we can parse a raw number from subPremise, add a '#' to the front, else take it as-is.
      if (int.tryParse(subPremise) != null) {
        subPremise = '#$subPremise';
      }

      streetAddress += ' $subPremise';
    }

    if (country == 'US') {
      // Right now, this is the only suffix we know how to handle
      if (postalCode != null && postalCodeSuffix != null) {
        postalCode = '$postalCode-$postalCodeSuffix';
      }
    }

    final address =
        Address(streetAddress, locality, admin1, admin2, postalCode, country);

    // Prevent the autocomplete controller from "hearing" this update, otherwise
    // it will attempt another Places Autocomplete API call with a new session token.
    // Doing this also prevents the autocomplete popup from reopening.
    _textEditingController.removeListener(_textEditingControllerListener);
    _textEditingController.text = streetAddress;
    _lastFieldValue = _textEditingController.text;
    _resetFieldDirtyFlag();
    _textEditingController.addListener(_textEditingControllerListener);

    widget.onSelected(address);
  }

  static String? _getAddressComponent(
    List<AddressComponent> components,
    String type, {
    bool shortName = true,
  }) {
    final matches = components
        .where((component) => component.types?.contains(type) ?? false);
    if (matches.isEmpty) {
      return null;
    }
    return shortName ? matches.first.shortName : matches.first.longName;
  }

  Widget _buildFieldView(
      BuildContext context,
      TextEditingController textEditingController,
      FocusNode focusNode,
      VoidCallback onFieldSubmitted) {
    return TextField(
      focusNode: focusNode,
      controller: _textEditingController,
      decoration: widget.textFieldConfiguration.decoration.copyWith(
        errorText: widget.textFieldConfiguration.decoration.errorText,
        suffixIcon: widget.onMapRequested == null
            ? null
            : InkResponse(
                radius: 24,
                canRequestFocus: true,
                onTap: widget.onMapRequested,
                child: const Icon(Icons.place),
              ),
      ),
      style: widget.textFieldConfiguration.style,
      textAlign: widget.textFieldConfiguration.textAlign,
      enabled: widget.textFieldConfiguration.enabled,
      keyboardType: widget.textFieldConfiguration.keyboardType,
      autofocus: widget.textFieldConfiguration.autofocus,
      inputFormatters: widget.textFieldConfiguration.inputFormatters,
      autocorrect: widget.textFieldConfiguration.autocorrect,
      maxLines: widget.textFieldConfiguration.maxLines,
      textAlignVertical: widget.textFieldConfiguration.textAlignVertical,
      minLines: widget.textFieldConfiguration.minLines,
      maxLength: widget.textFieldConfiguration.maxLength,
      maxLengthEnforcement: widget.textFieldConfiguration.maxLengthEnforcement,
      obscureText: widget.textFieldConfiguration.obscureText,
      onChanged: widget.textFieldConfiguration.onChanged,
      onSubmitted: (_) => onFieldSubmitted(),
      onEditingComplete: widget.textFieldConfiguration.onEditingComplete,
      onTap: widget.textFieldConfiguration.onTap,
      scrollPadding: widget.textFieldConfiguration.scrollPadding,
      textInputAction: widget.textFieldConfiguration.textInputAction,
      textCapitalization: widget.textFieldConfiguration.textCapitalization,
      keyboardAppearance: widget.textFieldConfiguration.keyboardAppearance,
      cursorWidth: widget.textFieldConfiguration.cursorWidth,
      cursorRadius: widget.textFieldConfiguration.cursorRadius,
      cursorColor: widget.textFieldConfiguration.cursorColor,
      textDirection: widget.textFieldConfiguration.textDirection,
      enableInteractiveSelection:
          widget.textFieldConfiguration.enableInteractiveSelection,
      readOnly: widget.readOnly,
    );
  }
}

class _AutocompleteResult {
  AutocompletePrediction prediction;

  _AutocompleteResult(this.prediction);

  String get optionString => prediction.description ?? 'Unknown';
}

class Address {
  Address(this.streetAddress, this.locality, this.administrativeAreaLevel1,
      this.administrativeAreaLevel2, this.postalCode, this.countryCode);

  /// The street address, e.g. "123 Anywhere St".
  String? streetAddress;

  /// The locality, typically the city.
  String? locality;

  /// Alias for [locality].
  String? get city => locality;

  /// The first administrative level, typically the state, province, or prefecture.
  String? administrativeAreaLevel1;

  /// Alias for [administrativeAreaLevel1];
  String? get state => administrativeAreaLevel1;

  /// The second administrative level, typically the county in the USA.
  String? administrativeAreaLevel2;

  /// Postal code. In the USA, this will include the ZIP+4 if it is provided.
  String? postalCode;

  /// ISO 3166-1 alpha-2 two letter country code.
  String? countryCode;
}

// From autocomplete.dart so that we can include the required "Powered By Google" logo.
class _AutocompleteOptions<T extends Object> extends StatelessWidget {
  const _AutocompleteOptions({
    Key? key,
    required this.displayStringForOption,
    required this.onSelected,
    required this.options,
    required this.poweredByGoogleLogo,
    this.maxOptionsWidth = 480,
  }) : super(key: key);

  final AutocompleteOptionToString<T> displayStringForOption;

  final AutocompleteOnSelected<T> onSelected;

  final Iterable<T> options;
  final double maxOptionsHeight = 300.0;
  final double? maxOptionsWidth;
  final Widget poweredByGoogleLogo;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: maxOptionsWidth ?? double.infinity,
              maxHeight: maxOptionsHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final T option = options.elementAt(index);
                  return InkWell(
                    onTap: () {
                      onSelected(option);
                    },
                    child: Builder(builder: (BuildContext context) {
                      final bool highlight =
                          AutocompleteHighlightedOption.of(context) == index;
                      if (highlight) {
                        SchedulerBinding.instance
                            .addPostFrameCallback((Duration timeStamp) {
                          Scrollable.ensureVisible(context, alignment: 0.5);
                        });
                      }
                      return Container(
                        color: highlight ? Theme.of(context).focusColor : null,
                        padding: const EdgeInsets.all(16.0),
                        child: Text(displayStringForOption(option)),
                      );
                    }),
                  );
                },
              ),
              poweredByGoogleLogo,
            ],
          ),
        ),
      ),
    );
  }
}

/// Supply an instance of this class to the [VscAddressLookupField.textFieldConfiguration]
/// property to configure the displayed text field
class TextFieldConfiguration {
  /// The decoration to show around the text field.
  ///
  /// Same as [TextField.decoration](https://docs.flutter.io/flutter/material/TextField/decoration.html)
  final InputDecoration decoration;

  /// Controls the text being edited.
  ///
  /// If null, this widget will create its own [TextEditingController](https://docs.flutter.io/flutter/widgets/TextEditingController-class.html).
  /// A typical use case for this field in the VscAddressLookupField widget is to set the
  /// text of the widget when a date is selected. For example:
  ///
  /// ```dart
  /// final _controller = TextEditingController();
  /// ...
  /// ...
  /// VscAddressLookupField(
  ///   controller: _controller,
  ///   ...
  ///   ...
  /// )
  /// ```
  final TextEditingController? controller;

  /// Controls whether this widget has keyboard focus.
  ///
  /// Same as [TextField.focusNode](https://docs.flutter.io/flutter/material/TextField/focusNode.html)
  final FocusNode? focusNode;

  /// The style to use for the text being edited.
  ///
  /// Same as [TextField.style](https://docs.flutter.io/flutter/material/TextField/style.html)
  final TextStyle? style;

  /// How the text being edited should be aligned horizontally.
  ///
  /// Same as [TextField.textAlign](https://docs.flutter.io/flutter/material/TextField/textAlign.html)
  final TextAlign textAlign;

  /// Same as [TextField.textDirection](https://docs.flutter.io/flutter/material/TextField/textDirection.html)
  ///
  /// Defaults to null
  final TextDirection? textDirection;

  /// Same as [TextField.textAlignVertical](https://api.flutter.dev/flutter/material/TextField/textAlignVertical.html)
  final TextAlignVertical? textAlignVertical;

  /// If false the textfield is "disabled": it ignores taps and its
  /// [decoration] is rendered in grey.
  ///
  /// Same as [TextField.enabled](https://docs.flutter.io/flutter/material/TextField/enabled.html)
  final bool enabled;

  /// The type of keyboard to use for editing the text.
  ///
  /// Same as [TextField.keyboardType](https://docs.flutter.io/flutter/material/TextField/keyboardType.html)
  final TextInputType keyboardType;

  /// Whether this text field should focus itself if nothing else is already
  /// focused.
  ///
  /// Same as [TextField.autofocus](https://docs.flutter.io/flutter/material/TextField/autofocus.html)
  final bool autofocus;

  /// Optional input validation and formatting overrides.
  ///
  /// Same as [TextField.inputFormatters](https://docs.flutter.io/flutter/material/TextField/inputFormatters.html)
  final List<TextInputFormatter>? inputFormatters;

  /// Whether to enable autocorrection.
  ///
  /// Same as [TextField.autocorrect](https://docs.flutter.io/flutter/material/TextField/autocorrect.html)
  final bool autocorrect;

  /// The maximum number of lines for the text to span, wrapping if necessary.
  ///
  /// Same as [TextField.maxLines](https://docs.flutter.io/flutter/material/TextField/maxLines.html)
  final int? maxLines;

  /// The minimum number of lines to occupy when the content spans fewer lines.
  ///
  /// Same as [TextField.minLines](https://docs.flutter.io/flutter/material/TextField/minLines.html)
  final int? minLines;

  /// The maximum number of characters (Unicode scalar values) to allow in the
  /// text field.
  ///
  /// Same as [TextField.maxLength](https://docs.flutter.io/flutter/material/TextField/maxLength.html)
  final int? maxLength;

  /// If true, prevents the field from allowing more than [maxLength]
  /// characters.
  ///
  /// Same as [TextField.maxLengthEnforcement](https://api.flutter.dev/flutter/material/TextField/maxLengthEnforcement.html)
  final MaxLengthEnforcement? maxLengthEnforcement;

  /// Whether to hide the text being edited (e.g., for passwords).
  ///
  /// Same as [TextField.obscureText](https://docs.flutter.io/flutter/material/TextField/obscureText.html)
  final bool obscureText;

  /// Called when the text being edited changes.
  ///
  /// Same as [TextField.onChanged](https://docs.flutter.io/flutter/material/TextField/onChanged.html)
  final ValueChanged<String>? onChanged;

  /// Called when the user indicates that they are done editing the text in the
  /// field.
  ///
  /// Same as [TextField.onSubmitted](https://docs.flutter.io/flutter/material/TextField/onSubmitted.html)
  final ValueChanged<String>? onSubmitted;

  /// The color to use when painting the cursor.
  ///
  /// Same as [TextField.cursorColor](https://docs.flutter.io/flutter/material/TextField/cursorColor.html)
  final Color? cursorColor;

  /// How rounded the corners of the cursor should be. By default, the cursor has a null Radius
  ///
  /// Same as [TextField.cursorRadius](https://docs.flutter.io/flutter/material/TextField/cursorRadius.html)
  final Radius? cursorRadius;

  /// How thick the cursor will be.
  ///
  /// Same as [TextField.cursorWidth](https://docs.flutter.io/flutter/material/TextField/cursorWidth.html)
  final double cursorWidth;

  /// The appearance of the keyboard.
  ///
  /// Same as [TextField.keyboardAppearance](https://docs.flutter.io/flutter/material/TextField/keyboardAppearance.html)
  final Brightness? keyboardAppearance;

  /// Called when the user submits editable content (e.g., user presses the "done" button on the keyboard).
  ///
  /// Same as [TextField.onEditingComplete](https://docs.flutter.io/flutter/material/TextField/onEditingComplete.html)
  final VoidCallback? onEditingComplete;

  /// Called for each distinct tap except for every second tap of a double tap.
  ///
  /// Same as [TextField.onTap](https://docs.flutter.io/flutter/material/TextField/onTap.html)
  final GestureTapCallback? onTap;

  /// Configures padding to edges surrounding a Scrollable when the Textfield scrolls into view.
  ///
  /// Same as [TextField.scrollPadding](https://docs.flutter.io/flutter/material/TextField/scrollPadding.html)
  final EdgeInsets scrollPadding;

  /// Configures how the platform keyboard will select an uppercase or lowercase keyboard.
  ///
  /// Same as [TextField.TextCapitalization](https://docs.flutter.io/flutter/material/TextField/textCapitalization.html)
  final TextCapitalization textCapitalization;

  /// The type of action button to use for the keyboard.
  ///
  /// Same as [TextField.textInputAction](https://docs.flutter.io/flutter/material/TextField/textInputAction.html)
  final TextInputAction? textInputAction;

  final bool enableInteractiveSelection;

  /// Creates a TextFieldConfiguration
  const TextFieldConfiguration({
    this.decoration = const InputDecoration(),
    this.style,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.maxLengthEnforcement,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.textAlignVertical,
    this.autocorrect = true,
    this.inputFormatters,
    this.autofocus = false,
    this.keyboardType = TextInputType.text,
    this.enabled = true,
    this.textAlign = TextAlign.start,
    this.focusNode,
    this.cursorColor,
    this.cursorRadius,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.cursorWidth = 2.0,
    this.keyboardAppearance,
    this.onEditingComplete,
    this.onTap,
    this.textDirection,
    this.scrollPadding = const EdgeInsets.all(20.0),
    this.enableInteractiveSelection = true,
  });

  /// Copies the [TextFieldConfiguration] and only changes the specified
  /// properties
  TextFieldConfiguration copyWith(
      {InputDecoration? decoration,
      TextStyle? style,
      TextEditingController? controller,
      ValueChanged<String>? onChanged,
      ValueChanged<String>? onSubmitted,
      bool? obscureText,
      MaxLengthEnforcement? maxLengthEnforcement,
      int? maxLength,
      int? maxLines,
      int? minLines,
      bool? autocorrect,
      List<TextInputFormatter>? inputFormatters,
      bool? autofocus,
      TextInputType? keyboardType,
      bool? enabled,
      TextAlign? textAlign,
      FocusNode? focusNode,
      Color? cursorColor,
      TextAlignVertical? textAlignVertical,
      Radius? cursorRadius,
      double? cursorWidth,
      Brightness? keyboardAppearance,
      VoidCallback? onEditingComplete,
      GestureTapCallback? onTap,
      EdgeInsets? scrollPadding,
      TextCapitalization? textCapitalization,
      TextDirection? textDirection,
      TextInputAction? textInputAction,
      bool? enableInteractiveSelection}) {
    return TextFieldConfiguration(
      decoration: decoration ?? this.decoration,
      style: style ?? this.style,
      controller: controller ?? this.controller,
      onChanged: onChanged ?? this.onChanged,
      onSubmitted: onSubmitted ?? this.onSubmitted,
      obscureText: obscureText ?? this.obscureText,
      maxLengthEnforcement: maxLengthEnforcement ?? this.maxLengthEnforcement,
      maxLength: maxLength ?? this.maxLength,
      maxLines: maxLines ?? this.maxLines,
      minLines: minLines ?? this.minLines,
      autocorrect: autocorrect ?? this.autocorrect,
      inputFormatters: inputFormatters ?? this.inputFormatters,
      autofocus: autofocus ?? this.autofocus,
      keyboardType: keyboardType ?? this.keyboardType,
      enabled: enabled ?? this.enabled,
      textAlign: textAlign ?? this.textAlign,
      textAlignVertical: textAlignVertical ?? this.textAlignVertical,
      focusNode: focusNode ?? this.focusNode,
      cursorColor: cursorColor ?? this.cursorColor,
      cursorRadius: cursorRadius ?? this.cursorRadius,
      cursorWidth: cursorWidth ?? this.cursorWidth,
      keyboardAppearance: keyboardAppearance ?? this.keyboardAppearance,
      onEditingComplete: onEditingComplete ?? this.onEditingComplete,
      onTap: onTap ?? this.onTap,
      scrollPadding: scrollPadding ?? this.scrollPadding,
      textCapitalization: textCapitalization ?? this.textCapitalization,
      textInputAction: textInputAction ?? this.textInputAction,
      textDirection: textDirection ?? this.textDirection,
      enableInteractiveSelection:
          enableInteractiveSelection ?? this.enableInteractiveSelection,
    );
  }
}
