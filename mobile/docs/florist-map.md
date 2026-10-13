# Nearby flower shops

The nearby-shop map uses `flutter_map` 8.3.2, `geolocator` 14.1.1, and a bundled
OpenStreetMap extract of Mongolia's `shop=florist` locations. It does not query
Overpass from users' phones. Shop coverage and details depend on contributions
to OpenStreetMap; an empty result means no catalog entry was found in the chosen
radius, not that the area has no flower shops. Distances are approximate straight
lines, not walking routes. Do not present opening hours as live availability.

Open **Нүүр → Ойрхон цэцгийн дэлгүүр** in the current Cloudflare app.
Pairing is not required. Choose **Ойролцоох дэлгүүр олох** for a foreground
location fix, or **Газрын зураг дээр сонгох** to start at central Ulaanbaatar
without device permission. Tap a point or pan and choose **Энэ хэсгээс хайх**.
The blue dot is the search origin; flower pins open a selected shop card.
The 5/10 km controls change the radius, and **Чиглэл** opens external directions.

The committed catalog contains 21 source entries, fetched from the Mongolia
administrative area at OSM base time `2026-10-13T06:20:50Z`. It includes 12
entries within 5 km of the public Ulaanbaatar reference point. These are OSM
records, not independently confirmed operating businesses or a complete list.
The original elements, source query, attribution and license link remain in
[`mongolia_florists.json`](../assets/maps/mongolia_florists.json). This extract
is available under the [Open Database License](https://opendatacommons.org/licenses/odbl/1-0/).
No commercial Maps/Places key is required and no paid search API is invoked.

To refresh, run the saved `query` once against the documented Overpass
interpreter as a maintenance action; reject a response containing `remark` or
invalid elements, retain source and license metadata, review changed records,
and update the catalog date displayed by `NearbyFloristsScreen`. Do not turn
this maintenance query into an automatic request from each user's phone.

## Location and privacy

- Opening the map does not request device location. The user chooses the location
  button or selects a point on the map manually.
- The location button obtains one foreground position with medium accuracy and a
  20-second acquisition limit. There is no continuous position stream or
  background tracking. Denial, disabled services, and timeout retain the manual
  map alternative.
- Device coordinates are used in memory to sort the bundled shops. They are not
  sent to the app's authentication/server endpoints, persisted as a user record,
  or shared with a partner.
- Displaying map tiles sends the requested map area and normal network metadata
  to OpenStreetMap's tile service. Tiles of viewed areas may remain in the map
  cache. This is not a promise that the viewed area is invisible to the provider.
- An external Google Maps directions link opens only on a user's tap and includes
  the selected shop destination. The app does not add the device coordinates as
  an origin. Google Maps may independently request/use location under its own
  permissions and privacy settings.

## Native setup

Android declares only `ACCESS_COARSE_LOCATION`. Approximate location is sufficient
for this feature; there is no `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`,
or app-added foreground location service permission. Android's existing Internet
permission covers map tiles. The resolved `geolocator_android` 5.1.1+1 plugin
declares an internal bound service that its initialization requires; that
declaration is not removed. The app does not configure foreground location
notifications or use the plugin's background stream. Approximate fixes can be
slow; the timeout and manual selection are intentional.

iOS declares a Mongolian `NSLocationWhenInUseUsageDescription` in
`ios/Runner/Info.plist`; no Always-purpose key or location background mode is
added. The repository uses the standard Flutter CocoaPods integration in
`ios/Podfile` and the Debug/Release Pod xcconfig includes. Its post-install hook
sets `BYPASS_PERMISSION_LOCATION_ALWAYS=1` on the **geolocator_apple Pod target**
for all configurations, preserving inherited definitions. A definition on only
Runner would not change the plugin's compilation.

This was checked against the locally resolved `geolocator_apple` 2.3.14 source.
The source requests When In Use when that purpose string exists. The compiler
definition also excludes its unused Always authorization branch. The plugin's
Swift package does not set that definition. Flutter 3.41.6 leaves Swift Package
Manager disabled by default, and this project's Xcode files have no SPM
integration. If migrating to SPM later, apply the equivalent definition to the
plugin package itself and recheck the archive; do not assume the Podfile hook
runs for an SPM dependency.

Verified locally: Info.plist parses with `plutil`, Podfile parses with Ruby, and
the permission declarations are foreground-only. **An iOS compile/archive and
real-device permission prompt remain unverified because full Xcode is absent on
this Mac.** After installing Xcode, run `flutter pub get`, install the Pods, and
build from `ios/Runner.xcworkspace`. Existing Apple signing and a two-device run
are still necessary. Android build/test evidence is recorded with the enclosing
change, not implied by these static native checks.

## Map provider and data maintenance

Keep visible, tappable **© OpenStreetMap contributors** attribution on the map,
linked to <https://www.openstreetmap.org/copyright>. Preserve source identifiers
and ODbL attribution with the bundled catalog so shop entries can be inspected
and corrected at their source. Refresh the extract intentionally; do not fabricate
shop names or use unverified seed locations as real businesses.

The standard tile endpoint is
`https://tile.openstreetmap.org/{z}/{x}/{y}.png`. Native requests identify the app
through `userAgentPackageName`; browser requests use the browser's User-Agent and
normal Referer behavior. The default `NetworkTileProvider` in flutter_map 8.3.2
keeps built-in native caching; web uses browser caching. Do not disable caching,
send no-cache headers, or introduce bulk/offline-area downloads. Keep visible
attribution unobscured when adding overlays.

The public tile service has no availability guarantee and may limit usage. A
larger release needs capacity review and, if necessary, a contracted tile
provider or self-hosted service before traffic grows. Substituting another
provider requires checking its URL, attribution, caching, and billing terms.

Official references checked for this change:

- [Geolocator setup and permissions](https://pub.dev/packages/geolocator)
- [Flutter Swift Package Manager integration](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)
- [OpenStreetMap tile usage policy](https://operations.osmfoundation.org/policies/tiles/)
- [OpenStreetMap data license and attribution](https://www.openstreetmap.org/copyright)
- [Google Maps directions URLs](https://developers.google.com/maps/documentation/urls/guide#directions-action)
