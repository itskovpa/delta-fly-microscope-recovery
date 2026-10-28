using Bonsai;
using System;
using System.ComponentModel;
using System.Collections.Generic;
using System.Linq;
using System.Reactive.Linq;
using OpenCV.Net;
using Bonsai.Vision;

[Combinator]
[Description("")]
[WorkflowElementCategory(ElementCategory.Transform)]
public class HeadTailVisualizer
{
    public static Point2f RotatePoint(Point2f pt, double rotRad)
    {
        Point2f result;
        result.X = pt.X * (float) Math.Cos(rotRad) + pt.Y * (float)Math.Sin(rotRad);
        result.Y = pt.X * (float) -Math.Sin(rotRad) + pt.Y * (float)Math.Cos(rotRad);

        return result;
    }
    public IObservable<IplImage> Process(IObservable<Tuple<IplImage, Point2f, Point2f>> source)
    {
        return source.Select(value => 
        {
            var image = value.Item1;
            var output = new IplImage(image.Size, image.Depth, 3);
            CV.CvtColor(image, output, ColorConversion.Gray2Bgr);
            
            var head = value.Item2;
            var tail = value.Item3;

            var OrientationVector = (head - tail)*0.6f;
            //Math.Atan2(OrientationVector.Y,OrientationVector.X);
            //var trans = new AffineTransform().

            var v2 = new Point(RotatePoint(OrientationVector,2.57f) + tail);
            var v3 = new Point (RotatePoint(OrientationVector,-2.57f) + tail);


            CV.Line(output, new Point(head), v2, Scalar.Rgb(204, 0, 0), 1);
            CV.Line(output, new Point(head), v3, Scalar.Rgb(0, 204, 0), 1);
            CV.Line(output, v2, v3, Scalar.Rgb(150, 150, 150), 1);
            

            //CV.Circle(output, new Point(head), 3, Scalar.Rgb(204, 0, 0), -1);
            //CV.Circle(output, new Point(tail), 3, Scalar.Rgb(0, 0, 204), -1);
            
            return output;
        
        });
    }
}
