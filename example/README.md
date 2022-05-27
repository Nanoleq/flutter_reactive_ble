# flutter_reactive_ble - Nanoleq fork

This repository is a fork of the original https://github.com/PhilipsHue/flutter_reactive_ble/.
This fork adds some support for Desktop (Macos and Windows) using the quick-blue package. Only
Macos has been tested so far.

At the time of writing, quick-blue did not seem to have the same level of readiness for production as
flutter_reactive_ble. Therefore it was decided to keep iOS and Android using flutter_reactive_ble while
supporting desktop by adding a thin wrapper on top of quick-blue to expose the same APIs as flutter_reactive_ble.

If support for desktop ever comes to flutter_reactive_ble, we will switch back to the non-forked version.