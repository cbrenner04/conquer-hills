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

## In the app

Each course file's `source.attribution` field carries its credit line, which the app must display (planned for the course detail screen, spec 07).
