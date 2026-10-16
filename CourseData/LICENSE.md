# Course data licences

The files under `CourseData/`, and the course files generated from them in `App/Resources/Courses/`, are derived from third-party open data. They carry the licences and credits below. The rest of this repository is not covered by these licences.

All courses are **unofficial**: they are reconstructed from public data for treadmill training and are not affiliated with or endorsed by any race organiser.

## OpenStreetMap (route geometry): ODbL 1.0

Route lines, OSM structure caches, and everything computed from them (distances along the route, sample positions, and the generated course files) are derived from OpenStreetMap.

> © OpenStreetMap contributors. Available under the Open Database License (ODbL) 1.0: <https://www.openstreetmap.org/copyright>, <https://opendatacommons.org/licenses/odbl/1-0/>.

These derived databases are made available under the ODbL 1.0. If you publicly use an adapted version, you must offer it under the ODbL too.

Affected files: `*/waypoints.geojson`, `*/route.json`, `*/osm-structures.json`, `*/elevation-samples.json`, and the generated `App/Resources/Courses/<id>.course.json` for each course here.

Waypoints are our own hand-picked points, mostly placed on OpenStreetMap junctions, so they are treated as derived too.

## Geospatial Information Authority of Japan (国土地理院): elevation (Tokyo)

> 標高データ：国土地理院 標高API（基盤地図情報 数値標高モデル）をもとに Conquer Hills が加工して作成
>
> Elevation: derived from Geospatial Information Authority of Japan (国土地理院) elevation data (elevation API, Fundamental Geospatial Data digital elevation model), processed by Conquer Hills.

The data is used under the GSI content terms (Public Data License 1.0, compatible with CC BY 4.0): <https://www.gsi.go.jp/kikakuchousei/kikakuchousei40182.html>. The values were processed (interpolated across bridges and lower-quality samples, smoothed, and converted to grades) and are not presented as GSI's own.

Affected files: `tokyo-marathon-2027/elevation-samples.json` and `App/Resources/Courses/tokyo-marathon-2027.course.json`.

## U.S. Geological Survey: elevation (Boston, Big Sur, Chicago, New York)

> Map services and data available from U.S. Geological Survey, National Geospatial Program. Elevation: U.S. Geological Survey 3D Elevation Program (1 m lidar DEMs), processed by Conquer Hills.

3DEP data is in the public domain ("free and in the public domain. There are no restrictions"; https://www.usgs.gov/faqs/what-are-terms-uselicensing-map-services-and-data-national-map). The acknowledgement above is the one USGS requests. The values were processed (interpolated across bridges, smoothed, and converted to grades). Nothing here implies USGS endorsement.

Affected files: `boston-marathon-2027/elevation-samples.json`, `big-sur-marathon-2027/elevation-samples.json`, `chicago-marathon-2026/elevation-samples.json`, `nyc-marathon-2026/elevation-samples.json`, and the matching `App/Resources/Courses/<id>.course.json` files.

### New York City Marathon: bridge decks

> Bridge deck elevations: 2017 NYC Topobathymetric Lidar (New York City Office of Technology and Innovation, via NOAA Digital Coast) and USGS 2014 New York City lidar, processed by Conquer Hills.

Bare-earth elevation data removes bridges, so the five bridge decks on the New York course (`nyc-marathon-2026/profiles.json`) are control points measured from public lidar point clouds: the 2017 NYC survey's bridge-deck class, and the USGS 2014 survey (public domain) where the 2017 survey has no returns. NOAA's metadata lists no use constraints; the data set's credit is the City of New York. The values were processed (medians along the roadway, points kept where the profile bends) and are not presented as the surveys' own.

Affected files: `nyc-marathon-2026/profiles.json`, `nyc-marathon-2026/elevation-samples.json` and `App/Resources/Courses/nyc-marathon-2026.course.json`. New York's distances are calibrated to mile and kilometre marks published on the course's 2022 USATF certification (NY22001JHP), stored as our own data points.

Distances for Boston are calibrated to a few street-corner mileages published on the course's USATF certification (MA21002JK), stored as our own data points in `config.json`; no part of the certificate is reproduced. Big Sur is calibrated the same way to its USATF certification (CA23018DT). Chicago is calibrated to the GPS split points published on its USATF certification (IL23038NM).

## In the app

Each course file's `source.attribution` field carries its credit line, which the app must display (planned for the course detail screen, spec 07).
