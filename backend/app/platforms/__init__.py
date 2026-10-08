"""Platform mappers (architecture.md D25, #323).

Pure functions from a platform's raw JSON to the wire models of
``app.keto.models``: no I/O, no clock, no logging, and none of them raises
on a malformed payload (the shapes a mapper does not know answer ``None``,
the Python twin of Dart's ``platformChanged``). Each module mirrors one Dart
mapper line by line, quirks included:

* ``wolt_menu`` mirrors ``WoltMenuMapper`` (``lib/services/menu/wolt/``);
* ``tenbis_menu`` mirrors ``TenBisMenuMapper`` (``lib/services/menu/tenbis/``);
* ``wolt_venues`` mirrors ``WoltVenueMapper`` (``lib/services/venue/wolt/``).

``_dart`` holds the few Dart runtime behaviours they share (``num`` checks,
``trim``, ``toString`` of a number, ``round``, ``Uri.toString``).
"""
