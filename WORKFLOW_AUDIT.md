# Historical Bonsai workflow audit

Scope: compared the three named delta workflows and the `Bonsai/ImageSta` experiment workflows by reading their XML and code only. No video or experimental-data files were opened. The saved-file timestamps are 9 Apr 2023, 10 Apr 2023, and 13 Apr 2023 respectively.

## Best recovery baseline

Use the **root `DeltaX2Move2PashaModifyed_Last_3cameras.bonsai` (10 Apr)** as the cleanest control-loop specification for a hardware-free revival. It keeps the active tracker, command builder, startup strings, and serial writer, while disabling the two separate MvCamCtrl capture/recording branches. Root reports a Bonsai 2.7.1 compile-only pass for this file; execution remains unverified. The tracker camera is selected only as `CameraCapture` index 0, the serialized X/Y divisors default to -100, and COM19 plus the camera driver are machine-specific. The 13 Apr copy is a detector/camera-setting variant, not evidence of a validated improvement.

| Saved workflow | Differences relevant to recovery |
|---|---|
| `DeltaX2Move2PashaModifyed_Last.bonsai` (9 Apr) | Tracker is `CameraCapture` index 0 with Exposure 4 / Settings 0; binary-inverse threshold 144 and contour MinArea 50. Two additional MvCamCtrl cameras (indices 0 and 1) and their video writers are enabled. |
| `DeltaX2Move2PashaModifyed_Last_3cameras.bonsai` (10 Apr) | Same tracker and control graph; threshold changed to 119. Both auxiliary MvCamCtrl capture → writer branches are wrapped in `Disable`. The filename does not add cameras: compared with 9 Apr, it turns off those two branches. |
| `Bonsai/ImageSta/DeltaX2Move2PashaModifyed_Last_3cameras.bonsai` (13 Apr) | Same controls and disabled auxiliary branches; tracker Exposure is -7 (the Settings assignment is removed), threshold is 163, and contour MinArea is 20. This is another parameter set, with no local evidence selecting it as better. |

Evidence: 9 Apr tracker and record branches: `DeltaX2Move2PashaModifyed_Last.bonsai:711-723, 766-783, 932-977`; 10 Apr: `DeltaX2Move2PashaModifyed_Last_3cameras.bonsai:711-723, 766-783, 932-989`; 13 Apr: `Bonsai/ImageSta/DeltaX2Move2PashaModifyed_Last_3cameras.bonsai:711-723, 762-777, 928-985`.

## Compile-only checks

The root agent reports that Bonsai 2.7.1 compile-only checks **pass** for the 10 Apr root workflow and the 13 Apr `Bonsai/ImageSta` copy. The 9 Apr root file **fails** with `Image is not a member of OpenCV.Net.IplImage`: its active `MvCamCtrlCapture` returns `IplImage`, but the following selector asks for `Image` (`DeltaX2Move2PashaModifyed_Last.bonsai:932-963`). The 10 Apr and 13 Apr workflows wrap those auxiliary MvCamCtrl capture → `MemberSelector Image` → writer branches in `Disable`, which avoids that compile path (`DeltaX2Move2PashaModifyed_Last_3cameras.bonsai:932-989`; 13 Apr copy: `Bonsai/ImageSta/DeltaX2Move2PashaModifyed_Last_3cameras.bonsai:928-985`). The root also reports compile-only passes for the earlier `DeltaX2Move2PashaModifyed.bonsai` and `DeltaX2Move2.bonsai`. None of these checks executed the workflow or tested hardware.

## Controls and serial protocol

The six direct keyboard jog groups are each direct children of a top-level `Disable`, so none is active as saved (`DeltaX2Move2PashaModifyed_Last.bonsai:32-277`). Their configured mappings are:

| Key | Serialized group | Command |
|---|---|---|
| Right | Right | `G0 X-1 F1000` |
| Left | Left | `G0 X1 F1000` |
| Up | Up | `G0 Y1 F1000` |
| A | Z_Down | `G0 Z-0.1 F1000` |
| Down | Down | `G0 Y-1 F1000` |
| Q | Z_Up | `G0 Z0.1 F1000` |

Each has `SuppressRepetitions=false`. The separate `MouseControl` group is also disabled; it uses Space to begin and End to stop generating mouse-derived XY commands (`:421-565`). The image-based `CommandsGain` group itself is enabled: S opens its `SkipUntil` gate and End terminates its `TakeUntil` stream (`:566-685`). The intended join is the named `XYCommand` stream: the active tracker has a `BehaviorSubject` named XYCommand (`:888-890`) and CommandsGain subscribes to that name (`:580-582`). A separate top-level XYCommand subject and the tracker’s trailing `MulticastSubject` are disabled (`:416-420, 891-895`), so this named-subject wiring still needs a no-hardware runtime check.

The output port named `Delta` is COM19, 115200 baud, no parity, 8 data bits, two stop bits, no handshake, DTR off, RTS on, and a 1-byte receive threshold (`:15-30`). `SerialStringWrite` appends CRLF (`:286-293`). `G28` is a separate string source into the named `Command` subject; another branch concatenates `G90`, `G01 Z-263 F100`, `G91`, `M203 S8000`, `M204 A20000`, `M205 S800`, with each item limited by `Take(1)` (`:278-367`). That `Concat` orders the six later strings, but the XML does not explicitly sequence `G28` ahead of them or wait for a response. These are G-code-like strings; the controller firmware and units are not included, so their exact semantics are unverified.

There is no acknowledgement dependency in this graph. The `SerialStringRead` on COM5 is disabled (`:387-394`), while the active writer output is sent to a CSV writer (`:286-301`). No read/ack stream gates startup commands or motion commands. The COM19 threshold setting alone is not an acknowledgement path.

## Vision feedback and motion law

The active tracking source in all three versions is the generic `cv:CameraCapture` index 0 (`:711-723`), not the two MvCamCtrl recorder sources. It is converted to grayscale and thresholded; the RangeThreshold and AdaptiveThreshold expressions are disabled, while fixed `Threshold` with `BinaryInv` is active. The versions use threshold 144 / 119 / 163 and MinArea 50 / 50 / 20 respectively. The graph finds connected components, analyzes the largest region, selects its centroid, and rejects NaN coordinates (`:725-818`; variant values above).

The configured 10-frame / skip-5 `WindowCount` is explicitly disabled (`:819-826`). An adjacent `CreateObservable` branch contains separate X/Y `Average` operations, but its effective smoothing behavior cannot be established from the XML alone (`:827-860`). The usable coordinate transform subtracts half the image width and height from centroid X/Y (`:870-883`), i.e. centers the pixel error around the frame center.

`CommandsGain` converts each centered coordinate to a float, then divides by an externalized `ScalingFactorX` or `ScalingFactorY` value. The serialized default for each divisor is `-100`, so the default transform is centered pixel error divided by -100; these are configured divisors, not missing multipliers (`:595-629`). Bonsai documents that `ExternalizedMapping` exposes an operator property on its containing group and that connecting a sequence maps values to that target property ([Property Mapping docs](https://github.com/bonsai-rx/docs/blob/main/articles/property-mapping.md)). The result is formatted to five decimal places and used to build `G01 X… Y…` (`:566-646`). The startup sequence ends in `G91`, so if the controller honors that mode, each image update is sent as a relative move. This is a scalar scaling of centered pixel error, not a documented PID; no deadband, calibrated pixel-to-mm scale, saturation, or motion-position feedback is serialized. S starts the output stream and End ends it.

## Separate ImageSta experiments

`Bonsai/ImageSta/camera.bonsai` is a **live camera/segmentation experiment**. Its generic `CameraCapture` index 1 is disabled; active MvCamCtrl index 1 supplies the image stream and writes `cam1`, while MvCamCtrl index 0 writes a separate `cam2` stream (`:13-53, 505-528`). The tracking branch uses grayscale, fixed inverse threshold 90, 3×3 rectangular dilation for 3 iterations, contour MinArea 200, and the largest-region centroid (`:55-138`). It zips this with a fixed point (637.059265, 370.380066), checks finite coordinates, then includes stabilization and head/tail/orientation/zoom visualization (`:134-168, 251-391, 418-500`). This workflow has no robot serial output.

`Bonsai/ImageSta/ImageSta.bonsai` is a separate **file-capture analysis composition**, not a live camera/robot workflow: it starts from `cv:FileCapture`, pairs it with a constant `Point2f(0,0)`, then includes `ValidPoint`, `Stabilizer`, `Zoomer`, `HeadTailGroup`, and `OrientationVisualizer` (`:9-40`). The extension files are reusable analysis blocks: `ValidPoint` filters non-finite XY (`Bonsai/ImageSta/extensions/ValidPoint.bonsai:11-29`); `Stabilizer` averages X and Y over six-sample windows, advancing by one (`Bonsai/ImageSta/extensions/Stabilizer.bonsai:19-70`); `HeadTailGroup` finds radial extremes and labels the endpoint farther from the blob centroid as head (`Bonsai/ImageSta/extensions/HeadTailGroup.bonsai:14-98, 115-135`); `Zoomer` makes a 72×72 crop (`Bonsai/ImageSta/extensions/Zoomer.bonsai:29-73`); `OrientationVisualizer` calls the custom `HeadTailVisualizer` (`Bonsai/ImageSta/extensions/OrientationVisualizer.bonsai:9-27`). These blocks help recover the image-analysis ideas, but they do not supply robot feedback or controller acknowledgements.

### Limits

This report recovers serialized intent and compile status, not successful runtime behavior. Camera indices are not hardware identities (the MvCamCtrl nodes leave SerialNumber blank), the delta workflow’s tracker camera index is host-dependent, and controller firmware is missing. The 10 Apr workflow is the most useful starting point for a new software-only specification, but none of the three can be called a verified functional baseline without execution evidence and the original camera/firmware configuration.
