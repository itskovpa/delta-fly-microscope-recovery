# Validation evidence

28 October 2026, Windows 11. No physical camera or robot used. No existing video or experimental-data file read.

| Check | Result |
|---|---|
| Historical sources | 40 files archived; SHA256 manifest; originals unchanged |
| Bonsai XML | 23 workflows parsed; zero out-of-range edge endpoints |
| Standalone source snapshot | Git archive exported and source preparation rerun without the surrounding lab folder; all 40 source checksums matched |
| Fresh environment restoration | Passed from empty runtime folder; 27 runtime packages, managed assembly files and native OpenCV checked; startup recheck exited 0 |
| Controller compilation | Apr 10, Apr 13 and working Apr 13 copy passed without executing |
| Camera-only tracking check | April 13 detector and centered X/Y output passed compile-only and static exclusion checks for serial, motion and recording; camera acquisition not executed |
| Historical Apr 9 compilation | Failed with surviving MvCamCtrl 0.1.0: `Image` is not a member of `IplImage`; documented compatibility discrepancy |
| Earlier candidates | `DeltaX2Move2.bonsai`, `DeltaX2Move2PashaModifyed.bonsai`, root camera check passed compilation |
| Apr 10 extracted pipeline | Passed: 80 frames generated, 8 blank, 72 commands, maximum absolute command-value error 0 |
| Apr 13 extracted pipeline | Passed: 80 frames generated, 8 blank, 72 commands, maximum absolute command-value error 0 |
| Bonsai MCP | Built without compiler errors; graph inspection and non-executing editor launch succeeded |
| UI visual inspection | Screen-capture approval timed out; actual S/End keyboard interaction not certified |
| User manual | Eight-page Word/PDF manual technically reviewed; all eight rendered pages inspected; zero out-of-page words and zero accessibility-audit issues |
| Portable binary release | `portable-2026.10.28`, built from `e7bb64fde8a3ab0c51dae816535ee115dd4334fb`: fresh extraction passed all 387 file hashes, five compile-only checks and both 80-frame synthetic tests with Python and dotnet absent from PATH and local-only package feeds; altered workflow rejected; public anonymous ZIP download SHA256 matched `3c95a967426d8f4568468c08e9071221786237bfa51e646b52fbf234e9d22d1e`. Test results and checksum are release assets. Windows system runtimes were already installed; physical hardware remains untested. |
| Physical behavior | Unverified: camera compatibility/settings, serial protocol/firmware, workspace, homing, axis scale/sign, motion stability, latency and sustained frame rate |

The synthetic input is a black radius-8 disk at four known locations in a white 320×240 image, with every tenth frame containing only a radius-1 distractor. Detector and command nodes are extracted from each historical file. Assertions compare every command against `(center - half_frame_size) / -100`, check counts, and reject missing results. The self-test bounds its output at 72 valid detections so persistent workflow elements cannot keep the test open indefinitely. The last valid detection occurs in frame 80.

Raw results: `offline-test-result-april10.json` and `offline-test-result-april13.json`. Local-only logs: `logs/validation-after-clean-restore.log`, `logs/clean-restore.log`, `logs/compile-candidates.log`, and `logs/mcp-*.json`.

The optional ImageSta file-analysis composition and older plotter/Magnet/FLIR workflows were not certified as a running stack. Their sources and dependency clues remain archived and described in the guide.

Navigation limitation: Graphify does not parse Bonsai workflow XML, and its shared NuGet node identifiers collapsed version labels from the historical ImageSta project and the new restore project. All version conclusions here were verified against the actual XML/package manifests and runtime; use `environment/Bonsai.config` and the lock file for the recovery dependencies.
