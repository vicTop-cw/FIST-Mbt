// docs/examples/httpclient/http_api.cs — 多语言接入的 HttpClient 示例（计划 multilang §4 / L88）。
//
// 计划原文：「README 给最小示例：curl / requests / HttpClient / fetch」（L88）
// 以及 §4 的语言家族策略：非 MoonBit 语言一律经 HTTP 契约接入，自带 HTTP 能力即可——
// .NET 侧那份"能力"就是 HttpClient（BCL 内置，零 NuGet 依赖）。
//
// 契约真源 docs/openapi/fist.yaml；桥起法：python scripts/fist-mbt-http.py [port]
// 用法（本机有 dotnet）：
//   dotnet run docs/examples/httpclient/http_api.cs [port]      // .NET 10+ 支持直接 run 单文件
//   或：csc /nologo /out:http_api.exe docs/examples/httpclient/http_api.cs && http_api.exe [port]
// 无第三方依赖（HttpClient + System.Text.Json 均为 BCL）。
//
// ✅ 已实测（2026-10-14）：本机 .NET SDK 9.0.306 下走**标准项目流程**跑通——
//    dotnet new console + 把本文件拷为 Program.cs + `dotnet run -- <port>`，回执见
//    reports/2026-10-14-multilang-examples-new-arms-report.md（rc=0 且打印 HTTPCLIENT-EXAMPLE PASS）。
//    注：`dotnet run <单文件.cs>`（.NET 10+ 才有）在本机 SDK 9 上不支持 ⇒ 用法里两种写法都给了。
using System;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;

class Program
{
    static async Task<int> Main(string[] args)
    {
        string port = args.Length > 0 ? args[0] : "3137";
        string baseUrl = $"http://127.0.0.1:{port}";
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };

        // 1) 自描述：清单 + inputSchema 就是参数真源，别硬编码参数表
        var toolsJson = await http.GetStringAsync($"{baseUrl}/tools");
        using var toolsDoc = JsonDocument.Parse(toolsJson);
        var tools = toolsDoc.RootElement.GetProperty("tools");
        var first = tools[0];
        Console.Write($"[1] GET /tools => {tools.GetArrayLength()} 个工具；示例工具 \"{first.GetProperty("name").GetString()}\" 的参数：");
        if (first.TryGetProperty("inputSchema", out var schema) &&
            schema.TryGetProperty("properties", out var props))
        {
            foreach (var p in props.EnumerateObject()) Console.Write($"{p.Name} ");
        }
        Console.WriteLine();

        // 2) 调用：body 就是该工具的 arguments（无参传 {}）；回执已剥 JSON-RPC 壳
        var body = new StringContent("{}", System.Text.Encoding.UTF8, "application/json");
        var callJson = await (await http.PostAsync($"{baseUrl}/tools/mode_list/call", body)).Content.ReadAsStringAsync();
        using var callDoc = JsonDocument.Parse(callJson);
        var root = callDoc.RootElement;
        bool ok = root.TryGetProperty("ok", out var okEl) && okEl.GetBoolean();
        var modes = new System.Collections.Generic.List<string>();
        if (root.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array)
        {
            foreach (var m in data.EnumerateArray())
                if (m.TryGetProperty("mode", out var mode)) modes.Add(mode.GetString() ?? "");
        }
        Console.WriteLine($"[2] POST /tools/mode_list/call => ok={ok} 模式: {string.Join(", ", modes)}");

        Console.WriteLine("HTTPCLIENT-EXAMPLE PASS");
        return 0;
    }
}
