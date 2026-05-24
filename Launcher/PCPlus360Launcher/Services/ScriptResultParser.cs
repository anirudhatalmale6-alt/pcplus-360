using System.Text.Json;

namespace PCPlus360Launcher.Services;

public static class ScriptResultParser
{
    public static object Parse(string rawOutput)
    {
        if (string.IsNullOrWhiteSpace(rawOutput))
            return new { raw = "" };

        var trimmed = rawOutput.Trim();

        // Try to find a JSON block in the output (scripts may emit non-JSON preamble)
        var jsonStart = FindJsonStart(trimmed);
        if (jsonStart >= 0)
        {
            var jsonCandidate = trimmed[jsonStart..];
            try
            {
                using var doc = JsonDocument.Parse(jsonCandidate);
                return JsonSerializer.Deserialize<object>(jsonCandidate)!;
            }
            catch (JsonException) { }
        }

        // Try parsing the entire output as JSON
        try
        {
            using var doc = JsonDocument.Parse(trimmed);
            return JsonSerializer.Deserialize<object>(trimmed)!;
        }
        catch (JsonException) { }

        // Fall back to raw text wrapped in an object
        return new { raw = trimmed };
    }

    public static List<Models.ScanResult> ParseScanResults(string rawOutput)
    {
        var results = new List<Models.ScanResult>();

        try
        {
            var parsed = Parse(rawOutput);
            var json = JsonSerializer.Serialize(parsed);
            using var doc = JsonDocument.Parse(json);

            if (doc.RootElement.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in doc.RootElement.EnumerateArray())
                {
                    results.Add(DeserializeScanResult(item));
                }
            }
            else if (doc.RootElement.TryGetProperty("results", out var arr) &&
                     arr.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in arr.EnumerateArray())
                {
                    results.Add(DeserializeScanResult(item));
                }
            }
            else
            {
                results.Add(DeserializeScanResult(doc.RootElement));
            }
        }
        catch
        {
            results.Add(new Models.ScanResult
            {
                Category = "Raw",
                Status = "Unknown",
                Message = rawOutput.Trim()
            });
        }

        return results;
    }

    private static Models.ScanResult DeserializeScanResult(JsonElement el)
    {
        return new Models.ScanResult
        {
            Category = el.TryGetProperty("category", out var c) ? c.GetString() ?? "" : "",
            Status = el.TryGetProperty("status", out var s) ? s.GetString() ?? "" : "",
            Message = el.TryGetProperty("message", out var m) ? m.GetString() ?? "" : "",
            Severity = el.TryGetProperty("severity", out var sv) ? sv.GetString() ?? "info" : "info",
            Details = el.TryGetProperty("details", out var d) ? d.GetString() : null
        };
    }

    private static int FindJsonStart(string text)
    {
        for (int i = 0; i < text.Length; i++)
        {
            if (text[i] == '{' || text[i] == '[')
                return i;
        }
        return -1;
    }
}
