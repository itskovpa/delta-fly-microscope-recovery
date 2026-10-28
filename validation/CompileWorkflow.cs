using System;
using System.Collections.Generic;
using System.IO;
using System.Linq.Expressions;
using System.Reflection;
using System.Xml;
using Bonsai;
using Bonsai.Expressions;

internal static class CompileWorkflow
{
    private static readonly Dictionary<string, string> Locations =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

    private static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.Error.WriteLine("Usage: CompileWorkflow.exe <runtime folder> <workflow file> [workflow file ...]");
            return 2;
        }

        try
        {
            string runtime = Path.GetFullPath(args[0]);
            var config = new XmlDocument();
            config.XmlResolver = null;
            config.Load(Path.Combine(runtime, "Bonsai.config"));
            foreach (XmlElement entry in config.SelectNodes("/PackageConfiguration/AssemblyLocations/AssemblyLocation"))
                Locations[entry.GetAttribute("assemblyName")] = Path.GetFullPath(Path.Combine(runtime, entry.GetAttribute("location")));
            AppDomain.CurrentDomain.AssemblyResolve += ResolveAssembly;
            string core;
            if (!Locations.TryGetValue("Bonsai.Core", out core))
                throw new FileNotFoundException("No AssemblyLocation for Bonsai.Core");
            Assembly.LoadFrom(core);
            foreach (XmlElement entry in config.SelectNodes("/PackageConfiguration/AssemblyReferences/AssemblyReference"))
            {
                string name = entry.GetAttribute("assemblyName");
                string location;
                if (!Locations.TryGetValue(name, out location))
                    throw new FileNotFoundException("No AssemblyLocation for " + name);
                Assembly.LoadFrom(location);
            }
            foreach (string extension in Directory.GetFiles(Path.Combine(runtime, "Extensions"), "*.dll"))
            {
                var assembly = Assembly.LoadFrom(extension);
                Locations[assembly.GetName().Name] = extension;
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("LOAD ERROR: runtime configuration or assembly preload");
            PrintException(ex);
            return 1;
        }

        int failures = 0;
        for (int i = 1; i < args.Length; i++)
        {
            try { if (!Validate(args[i])) failures++; }
            catch (Exception ex)
            {
                Console.Error.WriteLine("LOAD ERROR: " + args[i]);
                PrintException(ex);
                failures++;
            }
        }
        return failures == 0 ? 0 : 1;
    }

    private static Assembly ResolveAssembly(object sender, ResolveEventArgs args)
    {
        string path;
        return Locations.TryGetValue(new AssemblyName(args.Name).Name, out path) && File.Exists(path)
            ? Assembly.LoadFrom(path) : null;
    }

    private static void PrintException(Exception error)
    {
        Console.Error.WriteLine(error.ToString()); // Includes the ordinary inner-exception chain.
        for (Exception current = error; current != null; current = current.InnerException)
        {
            var typeLoad = current as ReflectionTypeLoadException;
            if (typeLoad != null)
                foreach (Exception loaderError in typeLoad.LoaderExceptions)
                    if (loaderError != null) Console.Error.WriteLine("Loader exception: " + loaderError);
            var aggregate = current as AggregateException;
            if (aggregate != null)
                foreach (Exception inner in aggregate.InnerExceptions)
                    if (inner != current.InnerException) Console.Error.WriteLine("Aggregate exception: " + inner);
        }
    }

    // Kept separate from Main so the resolver is registered before Bonsai is loaded.
    private static bool Validate(string file)
    {
        WorkflowBuilder builder;
        try
        {
            using (var reader = XmlReader.Create(file, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null }))
                builder = (WorkflowBuilder)WorkflowBuilder.Serializer.Deserialize(reader);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("LOAD ERROR: " + file);
            PrintException(ex);
            return false;
        }

        try
        {
            Expression expression = builder.Workflow.Build();
            Expression.Lambda(expression).Compile(); // Compile only: never invoke or subscribe.
            Console.WriteLine("COMPILE OK: " + file);
            return true;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("COMPILE ERROR: " + file);
            PrintException(ex);
            return false;
        }
    }
}
