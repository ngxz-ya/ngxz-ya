// Maintainer integration probe. Uses only the installed official NXOpen API.
// Batch geometry evidence only; does not claim an interactive live connection.
using System;
using System.IO;
using System.Globalization;
using NXOpen;
using NXOpen.Features;
using NXOpen.UF;
public class ActualGeometryProbe {
  public static void Main(string[] args) {
    string dir=args[0];
    double x=double.Parse(args[1],CultureInfo.InvariantCulture);
    if (x<=0 || double.IsInfinity(x) || double.IsNaN(x)) throw new ArgumentException("Invalid dimension");
    string file=Path.Combine(dir,"block-"+x.ToString(CultureInfo.InvariantCulture)+".prt");
    Session s=Session.GetSession();
    if(args.Length>2 && args[2]=="verify") {
      PartLoadStatus load;
      Part reopened=(Part)s.Parts.OpenDisplay(file,out load); load.Dispose();
      Body[] readBodies=reopened.Bodies.ToArray();
      if(readBodies.Length!=1) throw new Exception("Unexpected saved body count");
      double[] readBox=new double[6]; UFSession.GetUFSession().Modl.AskBoundingBox(readBodies[0].Tag,readBox);
      double dx=readBox[3]-readBox[0], dy=readBox[4]-readBox[1], dz=readBox[5]-readBox[2];
      Console.WriteLine("INDEPENDENT_READBACK "+string.Join(",",Array.ConvertAll(new double[]{dx,dy,dz},v=>v.ToString("R",CultureInfo.InvariantCulture))));
      if(Math.Abs(dx-x)>0.001 || Math.Abs(dy-12)>0.001 || Math.Abs(dz-14)>0.001) throw new Exception("Saved geometry mismatch");
      Console.WriteLine("INDEPENDENT_GEOMETRY_PASS"); return;
    }
    if (File.Exists(file)) throw new IOException("Refuse overwrite");
    Part p=s.Parts.NewDisplay(file,Part.Units.Millimeters);
    BlockFeatureBuilder b=p.Features.CreateBlockFeatureBuilder(null);
    b.SetOriginAndLengths(new Point3d(0,0,0),"10","12","14");
    Feature f=b.CommitFeature(); b.Destroy();
    Session.UndoMarkId mark=s.SetUndoMark(Session.MarkVisibility.Invisible,"probe edit");
    Expression length=null;
    foreach(Expression e in f.GetExpressions()) {
      Console.WriteLine("EXPRESSION "+e.Name+"="+e.RightHandSide);
      if(Math.Abs(e.Value-10)<0.000001) length=e;
    }
    if(length==null) throw new Exception("Missing length expression");
    p.Expressions.Edit(length,x.ToString(CultureInfo.InvariantCulture));
    s.UpdateManager.DoUpdate(mark);
    UFSession.GetUFSession().Modl.Update();
    Body[] bodies=p.Bodies.ToArray();
    if(bodies.Length!=1) throw new Exception("Unexpected body count");
    double[] box=new double[6]; UFSession.GetUFSession().Modl.AskBoundingBox(bodies[0].Tag,box);
    double[] actual={box[3]-box[0],box[4]-box[1],box[5]-box[2]};
    Console.WriteLine("ACTUAL "+string.Join(",",Array.ConvertAll(actual,v=>v.ToString("R",CultureInfo.InvariantCulture))));
    if(Math.Abs(actual[0]-x)>0.001 || Math.Abs(actual[1]-12)>0.001 || Math.Abs(actual[2]-14)>0.001) throw new Exception("Geometry verification failed");
    PartSaveStatus status=p.Save(BasePart.SaveComponents.True,BasePart.CloseAfterSave.False); status.Dispose();
    File.WriteAllText(Path.Combine(dir,"measurement-"+x.ToString(CultureInfo.InvariantCulture)+".txt"),string.Join(",",Array.ConvertAll(actual,v=>v.ToString("R",CultureInfo.InvariantCulture))));
    Console.WriteLine("ACTUAL_GEOMETRY_PASS "+file);
  }
  public static int GetUnloadOption(string dummy) { return (int)Session.LibraryUnloadOption.Immediately; }
}
