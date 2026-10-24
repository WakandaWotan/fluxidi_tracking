# Driver 1.0.7 (114) — integrated candidate

`source/` contains the complete B113 released source closure with the approved QR, sidebar, alert and canonical assignment refresh corrections. SOURCE-HASHES.json pins every file. Backend source is in the parent commit's releases/backend/booking-preview-20261024-e0270b2c198e.

No signing keys, production defines, local SDK configuration, request captures or AABs are included. Supply the existing authorized external signing properties and production Dart-defines when reproducing the build. RELEASE.json pins their nonsecret expected hashes/certificate and the backend parent.

Build from this committed directory with Flutter3.35.5/Dart3.9.2 and locked dependencies. Run tests with the existing local fixture settings where required. Before a release build restore the exact committed release GeneratedPluginRegistrant.java after pub/test generation, so integration_test is never bundled.

Physical device validation remains OPEN. Do not create the final release tag before owner-confirmed Samsung acceptance. Decision HTTP200 is not canonical assignment. The existing assignment_driver_no_vehicle and physical navigation issues are not claimed fixed by this client candidate.
