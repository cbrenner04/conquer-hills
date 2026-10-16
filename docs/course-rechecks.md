# Course re-checks

Each bundled course is a snapshot of one edition of a real race. Organisers change routes for road works, crowd flow or landslides, usually announcing the change with the next course map. This list says when each course's next official information usually appears and what to compare.

## How to re-check a course

1. Open the official course page in the window below and find the new course map, participant guide or measurement certificate.
2. Compare it with the course's review report (`make course-report ID=<id>`): the streets in order, turnarounds, the start and finish, and the checkpoint positions in `CourseData/<id>/config.json`.
3. If nothing changed, update the course's row here with the date checked.
4. If the route changed, fix `waypoints.geojson` (or the route relation) and `config.json`, rebuild with the pipeline, and open a PR for the course. If the edition changes, the course id and `edition` change with it.

Use official pages only to read facts such as street names and distances. Never commit organisers' maps, route files or certificates (see `CourseData/LICENSE.md`).

## Schedule

| Course | Edition modelled | Next race | Re-check | Where | What could change |
| --- | --- | --- | --- | --- | --- |
| `big-sur-marathon-2027` | 2027 (certified course CA23018DT, valid to 2033) | 25 Apr 2027 | March 2027, and again in April | <https://bigsurmarathon.org/> | Landslides on Highway 1 have turned the race into a one-year out-and-back from Carmel (1998, 2011, 2024), announced as late as 11 days before the race. Keep the standard point-to-point course and mention any one-year change in the course notes. |
| `boston-marathon-2027` | 2027 (certified course MA21002JK) | 19 Apr 2027 | Feb–Mar 2027, when the 2027 map and participant guide appear | <https://www.baa.org/races/boston-marathon/the-course/> | Road works near the Charlesgate (Bowker Overpass) at about 41 km. |
| `chicago-marathon-2026` | 2026 (certified course IL23038NM, re-measured Sep 2026, valid to 2033) | 10 Oct 2027 | Late Aug 2027, when the 2027 map appears | <https://www.chicagomarathon.com/runners/course/> | Mile 2 runs on Dearborn St while State St is under construction (to about 2029); if 2027 reverts to State St, re-route that stretch. If unchanged, relabel the edition 2027. |
| `nyc-marathon-2026` | 2026 (Blue start; 2026 Bronx change; calibrated to the 2022 certificate NY22001JHP) | 1 Nov 2026 | After 1 Nov 2026, for a 2026 USATF certificate; and Sep 2027, when the 2027 maps appear | <https://www.nyrr.org/tcsnycmarathon/the-course>; USATF course database | The 2026 Bronx change voids the 2022 certificate, so miles 20–21 are estimated; re-anchor the Bronx with the new certificate's marks. If 2027 is unchanged, keep the id. |
| `tokyo-marathon-2027` | 2027 | 7 Mar 2027 | Jan–Feb 2027, and again when the participant guide appears, about a month before the race | <https://www.marathon.tokyo/en/about/course/> | Construction, as in 2021, for example the expressway works around Nihombashi. Compare the three turnarounds and the checkpoint table. |
