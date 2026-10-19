# Course data licences

The files under `CourseData/`, and the course files generated from them in `App/Resources/Courses/`, are derived from third-party open data. They carry the licences and credits below. The rest of this repository is not covered by these licences.

All courses are **unofficial**: they are reconstructed from public data for treadmill training and are not affiliated with or endorsed by any race organiser.

## OpenStreetMap (route geometry): ODbL 1.0

Route lines, OSM structure caches, and everything computed from them (distances along the route, sample positions, and the generated course files) are derived from OpenStreetMap.

> © OpenStreetMap contributors. Available under the Open Database License (ODbL) 1.0: <https://www.openstreetmap.org/copyright>, <https://opendatacommons.org/licenses/odbl/1-0/>.

These derived databases are made available under the ODbL 1.0. If you publicly use an adapted version, you must offer it under the ODbL too.

Affected files: `*/waypoints.geojson`, `*/route.json`, `*/osm-structures.json`, `*/elevation-samples.json`, and the generated `App/Resources/Courses/<id>.course.json` for each course here.

Waypoints are our own hand-picked points, mostly placed on OpenStreetMap junctions, so they are treated as derived too.

## Environment Agency: elevation (London)

> Elevation: © Environment Agency copyright and/or database right 2022. Contains public sector information licensed under the Open Government Licence v3.0. Processed by Conquer Hills.

The Environment Agency's LIDAR Composite DTM 1 m (2022) is published under the Open Government Licence v3.0 (<https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/>), with the attribution statement above. The values were read as small grids from the public WCS (coverage `Lidar_Composite_Elevation_DTM_1m`) and processed (interpolated between grid cells and across bridges, smoothed, and converted to grades). Nothing here suggests any official status or endorsement.

Affected files: `london-marathon-2027/elevation-samples.json` and `App/Resources/Courses/london-marathon-2027.course.json`. London's distances are scaled between the start and the finish and compared with the organiser's published mile-by-mile road list, stored as our own data points.

## Geoportal Berlin: elevation (Berlin)

> Elevation: Digitales Geländemodell DGM1, © Geoportal Berlin (dl-de/zero-2-0), processed by Conquer Hills.

Berlin's official 1 m terrain model (Senatsverwaltung für Stadtentwicklung, Bauen und Wohnen) is published under the Datenlizenz Deutschland – Zero – Version 2.0, which permits any use without conditions and requires no attribution; we credit it anyway. The values were read point by point from the public WMS (layer `c_dgm1`) and processed (interpolated across bridges, smoothed, and converted to grades).

Affected files: `berlin-marathon-2027/elevation-samples.json` and `App/Resources/Courses/berlin-marathon-2027.course.json`. Berlin's distances are compared with the course's bridges and the Brandenburg Gate at distances the organiser publishes, stored as our own data points.

## City of Cape Town: elevation (Cape Town)

> Elevation: City of Cape Town LiDAR (2025 2 m digital terrain model), processed by Conquer Hills.

The City publishes its lidar elevation models as open data under its Open Data Policy (Policy 27781, 2020), which defines open data as data that "can be freely used, shared and built-on by anyone, anywhere, for any purpose"; its open data terms of use provide the data "as is" and name no licence or attribution clause. We credit the City anyway. The values were read point by point from the City's public WMS (layer `Elevation_DTM_2m`, source file `LiDAR2025_2m_DTM_v1.tif`) and processed (interpolated across bridges and the elevated N2, smoothed, and converted to grades). Nothing here implies the City's endorsement.

Affected files: `cape-town-marathon-2027/elevation-samples.json` and `App/Resources/Courses/cape-town-marathon-2027.course.json`. Cape Town's distances are calibrated to km points the organiser publishes for spectators, stored as our own data points.

## Shanghai: modelled elevation (no data source)

> Elevation: modelled as flat (central Shanghai ≈ 4 m) with bridge humps at creek crossings from OpenStreetMap; not measured.

No open elevation data measures the ground in Shanghai: global models (Copernicus GLO-30, SRTM, ASTER) are surface models that read the city's buildings and elevated roads, with hundreds of metres of false gain along the course. `shanghai-marathon-2026/elevation-samples.json` therefore holds a constant 4 m from the pipeline's `flat` provider, and `shanghai-marathon-2026/profiles.json` adds a modelled 2 m hump at each creek bridge the course crosses: positions from OpenStreetMap (ODbL), heights assumed. Nothing in these files is a survey result.

Affected files: `shanghai-marathon-2026/elevation-samples.json`, `shanghai-marathon-2026/profiles.json` and `App/Resources/Courses/shanghai-marathon-2026.course.json`. The street sequence comes from the Shanghai Public Security Bureau's race-day traffic notice (facts, not copied text).

## Geospatial Information Authority of Japan (国土地理院): elevation (Tokyo)

> 標高データ：国土地理院 標高API（基盤地図情報 数値標高モデル）をもとに Conquer Hills が加工して作成
>
> Elevation: derived from Geospatial Information Authority of Japan (国土地理院) elevation data (elevation API, Fundamental Geospatial Data digital elevation model), processed by Conquer Hills.

The data is used under the GSI content terms (Public Data License 1.0, compatible with CC BY 4.0): <https://www.gsi.go.jp/kikakuchousei/kikakuchousei40182.html>. The values were processed (interpolated across bridges and lower-quality samples, smoothed, and converted to grades) and are not presented as GSI's own.

Affected files: `tokyo-marathon-2027/elevation-samples.json` and `App/Resources/Courses/tokyo-marathon-2027.course.json`.

## Geoscience Australia: elevation (Sydney)

> Elevation: Digital Elevation Model of Australia derived from LiDAR 5 Metre Grid, © Commonwealth of Australia (Geoscience Australia), CC BY 4.0, processed by Conquer Hills.

Used under the Creative Commons Attribution 4.0 International licence (Geoscience Australia catalogue record 89644). The values were processed (interpolated across bridges, viaducts and noisy stretches, smoothed, and converted to grades). The Harbour Bridge deck (`sydney-marathon-2027/profiles.json`) is modelled from a published height (52 m above the water, Engineers Australia), not measured.

Affected files: `sydney-marathon-2027/elevation-samples.json`, `sydney-marathon-2027/profiles.json` and `App/Resources/Courses/sydney-marathon-2027.course.json`. Sydney's distances are calibrated to the course's U-turns and finish at the distances the organiser publishes, stored as our own data points.

## U.S. Geological Survey: elevation (Boston, Big Sur, Chicago, New York, Leadville, Blue Ridge)

> Map services and data available from U.S. Geological Survey, National Geospatial Program. Elevation: U.S. Geological Survey 3D Elevation Program (1 m lidar DEMs), processed by Conquer Hills.

3DEP data is in the public domain ("free and in the public domain. There are no restrictions"; https://www.usgs.gov/faqs/what-are-terms-uselicensing-map-services-and-data-national-map). The acknowledgement above is the one USGS requests. The values were processed (interpolated across bridges, smoothed, and converted to grades). Nothing here implies USGS endorsement.

Affected files: `boston-marathon-2027/elevation-samples.json`, `big-sur-marathon-2027/elevation-samples.json`, `chicago-marathon-2026/elevation-samples.json`, `nyc-marathon-2026/elevation-samples.json`, `leadville-trail-marathon-2027/elevation-samples.json`, `blue-ridge-marathon-2026/elevation-samples.json`, and the matching `App/Resources/Courses/<id>.course.json` files.

### New York City Marathon: bridge decks

> Bridge deck elevations: 2017 NYC Topobathymetric Lidar (New York City Office of Technology and Innovation, via NOAA Digital Coast) and USGS 2014 New York City lidar, processed by Conquer Hills.

Bare-earth elevation data removes bridges, so the five bridge decks on the New York course (`nyc-marathon-2026/profiles.json`) are control points measured from public lidar point clouds: the 2017 NYC survey's bridge-deck class, and the USGS 2014 survey (public domain) where the 2017 survey has no returns. NOAA's metadata lists no use constraints; the data set's credit is the City of New York. The values were processed (medians along the roadway, points kept where the profile bends) and are not presented as the surveys' own.

Affected files: `nyc-marathon-2026/profiles.json`, `nyc-marathon-2026/elevation-samples.json` and `App/Resources/Courses/nyc-marathon-2026.course.json`. New York's distances are calibrated to mile and kilometre marks published on the course's 2022 USATF certification (NY22001JHP), stored as our own data points.

Distances for Boston are calibrated to a few street-corner mileages published on the course's USATF certification (MA21002JK), stored as our own data points in `config.json`; no part of the certificate is reproduced. Big Sur is calibrated the same way to its USATF certification (CA23018DT). Chicago is calibrated to the GPS split points published on its USATF certification (IL23038NM). Blue Ridge is calibrated to mile points on its USATF certification (VA24031RT), four of them and the greenway turnaround located by GPS on the certificate. Leadville is uncertified: it is scaled to its stated 26.4 miles between the Mosquito Pass turnaround and the finish, and compared with its aid stations' published mileages, stored as our own data points.

## In the app

Each course file's `source.attribution` field carries its credit line, which the app must display (planned for the course detail screen, spec 07).
