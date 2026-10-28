using System;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reactive.Linq;
using System.Xml.Serialization;
using Bonsai;
using OpenCV.Net;

namespace Recovery
{
    [XmlType(Namespace = "clr-namespace:Recovery;assembly=Recovery.Offline")]
    [Description("Artificial dark disk on a bright 320x240 image. Never accesses a camera.")]
    public class SyntheticFly : Source<IplImage>
    {
        public SyntheticFly() { FrameCount = 80; }
        public int FrameCount { get; set; }
        public static int FramesGenerated { get; private set; }
        public static int BlankFramesGenerated { get; private set; }

        public static Point Position(long index)
        {
            Point[] points = { new Point(120, 100), new Point(160, 120), new Point(200, 140), new Point(180, 80) };
            return points[index % points.Length];
        }

        public override IObservable<IplImage> Generate()
        {
            // Deliberately fixed for this test. Historical command formatting uses the OS culture.
            CultureInfo.DefaultThreadCurrentCulture = CultureInfo.InvariantCulture;
            FramesGenerated = BlankFramesGenerated = 0;
            var clock = Observable.Interval(TimeSpan.FromMilliseconds(40));
            if (FrameCount > 0) clock = clock.Take(FrameCount);
            return clock.Select(index =>
            {
                var image = new IplImage(new Size(320, 240), IplDepth.U8, 3);
                image.Set(Scalar.All(255));
                if (index % 10 != 0) CV.Circle(image, Position(index), 8, Scalar.All(0), -1);
                else BlankFramesGenerated++;
                FramesGenerated++;
                // A second component below the historical minimum contour area.
                CV.Circle(image, new Point(25, 25), 1, Scalar.All(0), -1);
                return image;
            });
        }
    }

    [XmlType(Namespace = "clr-namespace:Recovery;assembly=Recovery.Offline")]
    public class AutomaticStart : Source<long>
    {
        public override IObservable<long> Generate() { return Observable.Return(0L); }
    }

    [XmlType(Namespace = "clr-namespace:Recovery;assembly=Recovery.Offline")]
    public class AutomaticStop : Source<long>
    {
        public override IObservable<long> Generate() { return Observable.Timer(TimeSpan.FromSeconds(6)); }
    }

    [XmlType(Namespace = "clr-namespace:Recovery;assembly=Recovery.Offline")]
    [Description("Displays robot command strings without opening a serial port. Self-test checks known disk locations.")]
    public class CommandProbe : Transform<string, string>
    {
        public CommandProbe() { Verify = true; }
        public bool Verify { get; set; }

        public override IObservable<string> Process(IObservable<string> source)
        {
            return Observable.Defer(() =>
            {
                var expected = Enumerable.Range(0, 80).Where(i => i % 10 != 0).Select(i => SyntheticFly.Position(i)).ToArray();
                int count = 0;
                double maxError = 0;
                if (Verify) source = source.Take(expected.Length);
                return source.Do(command =>
                {
                    if (!command.StartsWith("G01 X", StringComparison.Ordinal)) return;
                    Console.WriteLine(command);
                    if (Verify)
                    {
                        if (count >= expected.Length) throw new InvalidOperationException("Unexpected extra tracking command.");
                        var parts = command.Substring(5).Split(new[] { " Y" }, StringSplitOptions.None);
                        double actualX = double.Parse(parts[0], CultureInfo.InvariantCulture);
                        double actualY = double.Parse(parts[1], CultureInfo.InvariantCulture);
                        double expectedX = (expected[count].X - 160) / -100.0;
                        double expectedY = (expected[count].Y - 120) / -100.0;
                        maxError = Math.Max(maxError, Math.Max(Math.Abs(actualX - expectedX), Math.Abs(actualY - expectedY)));
                        if (maxError > 0.00001) throw new InvalidOperationException("Tracking command differs from the known disk position at command " + count);
                    }
                    count++;
                }, () =>
                {
                    if (!Verify) return;
                    if (count != expected.Length) throw new InvalidOperationException("Expected " + expected.Length + " tracking commands; received " + count);
                    if (SyntheticFly.FramesGenerated != 80 || SyntheticFly.BlankFramesGenerated != 8)
                        throw new InvalidOperationException("Synthetic frame counts differ from the test specification.");
                    string result = "{\"passed\":true,\"synthetic_frames\":80,\"blank_frames\":8,\"tracking_commands\":" + count +
                        ",\"max_command_error\":" + maxError.ToString("R", CultureInfo.InvariantCulture) +
                        ",\"hardware_access\":false,\"physical_performance_validated\":false}";
                    File.WriteAllText("offline-test-result.json", result);
                    Console.WriteLine("OFFLINE SELF-TEST PASSED: " + result);
                });
            });
        }
    }
}
