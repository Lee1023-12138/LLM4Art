// Multi-provider backend (Gemini + OpenAI) — Node + Express
const express = require("express");
const cors = require("cors");
const path = require("path");
const dotenv = require("dotenv");
dotenv.config(); // If you put .env in App/, you can do this; if it is not the default path: dotenv.config({ path: path.join(__dirname, ".env") });

/* --- SDKs --- */
const { GoogleGenerativeAI } = require("@google/generative-ai");
const OpenAI = require("openai/index.js"); // npm i openai

const app = express();
app.use(cors());
app.use(express.json({ limit: "25mb" }));

app.get("/api/health", (req, res) => {
  res.json({
    ok: true,
    service: "llm4art-backend",
    provider: process.env.PROVIDER || "gemini",
  });
});

/* ---------- Utils ---------- */
function parseDataUrl(dataUrl) {
  const m = /^data:(.+?);base64,(.+)$/.exec(dataUrl || "");
  if (!m) return null;
  return { mimeType: m[1], data: m[2] };
}
function stripCodeFence(s) {
  if (!s) return s;
  return s.replace(/^```json\s*/i, "").replace(/^```\s*/i, "").replace(/```$/i, "").trim();
}
function normalizeReport(parsedJson) {
  const meta = parsedJson?.meta || {};
  const sections = parsedJson?.sections || {};
  return {
    meta: {
      title: meta.title || "—",
      artist: meta.artist || "—",
      year: meta.year || "—",
      medium: meta.medium || "—",
      region: meta.region || "—",
      notes: meta.notes || "",
    },
    sections: {
      visual: sections.visual || "—",
      genre: sections.genre || "—",
      color: sections.color || "—",
      line: sections.line || "—",
      shape: sections.shape || "—",
      artifact: sections.artifact || "—",
      historical: sections.historical || "—",
      cultural: sections.cultural || "—",
    },
  };
}

/* ---------- Shared prompt ---------- */
const SYSTEM_PROMPT = `
You are an expert art historian. Analyze ONLY the provided image.

Return STRICT JSON with this exact schema:

{
  "meta": {
    "title": "— or inferred short title",
    "artist": "— or inferred",
    "year": "— or 4-digit if confidently inferred",
    "medium": "— or inferred (e.g., Oil on canvas / Fresco / Photograph / Digital)",
    "region": "— or inferred culture/region",
    "notes": "brief optional notes"
  },
  "sections": {
    "visual": "concise visual analysis",
    "genre": "genre/style identification",
    "color": "color palette / mood",
    "line": "line & perspective",
    "shape": "shape & form",
    "artifact": "artifact type / medium discussion",
    "historical": "historical context (avoid hallucinating specifics)",
    "cultural": "cultural significance (avoid speculation)"
  }
}

If uncertain about any field, use "—" rather than guessing. Keep prose concise and factual.
Language: follow the user's interface language if possible (Chinese if inputs look Chinese).
`.trim();

/* ---------- Provider: Gemini ---------- */
async function analyzeWithGemini({ imageDataUrl }) {
  const API_KEY = process.env.GOOGLE_API_KEY;
  const MODEL = process.env.GOOGLE_MODEL || "gemini-1.5-flash";
  if (!API_KEY) throw new Error("Missing GOOGLE_API_KEY");

  const parsed = parseDataUrl(imageDataUrl);
  if (!parsed) throw new Error("Invalid dataURL");

  const genAI = new GoogleGenerativeAI(API_KEY);
  const model = genAI.getGenerativeModel({ model: MODEL });

  const result = await model.generateContent({
    contents: [
      {
        role: "user",
        parts: [
          { text: SYSTEM_PROMPT },
          { inlineData: { mimeType: parsed.mimeType, data: parsed.data } },
        ],
      },
    ],
    generationConfig: { temperature: 0.4, maxOutputTokens: 2048 },
  });

  const text =
    result?.response?.text?.() ||
    result?.response?.candidates?.[0]?.content?.parts?.[0]?.text ||
    "";
  const content = stripCodeFence(text);

  let parsedJson;
  try {
    parsedJson = JSON.parse(content);
  } catch (e) {
    return { error: "Gemini returned non-JSON", raw: content };
  }
  return normalizeReport(parsedJson);
}

/* ---------- Provider: OpenAI (GPT) ---------- */
async function analyzeWithOpenAI({ imageDataUrl }) {
  const API_KEY = process.env.OPENAI_API_KEY;
  const MODEL = process.env.OPENAI_MODEL || "gpt-4o-mini";
  if (!API_KEY) throw new Error("Missing OPENAI_API_KEY");

  const client = new OpenAI({ apiKey: API_KEY });

  // OpenAI supports dataURL as image_url directly passed in
  const messages = [
    { role: "system", content: SYSTEM_PROMPT },
    {
      role: "user",
      content: [
        { type: "text", text: "Analyze this artwork and return the strict JSON." },
        { type: "image_url", image_url: { url: imageDataUrl } },
      ],
    },
  ];

  // Output JSON
  const resp = await client.chat.completions.create({
    model: MODEL,
    messages,
    temperature: 0.4,
    response_format: { type: "json_object" },
  });

  const content = resp?.choices?.[0]?.message?.content || "";
  let parsedJson;
  try {
    parsedJson = JSON.parse(content);
  } catch (e) {

    try {
      parsedJson = JSON.parse(stripCodeFence(content));
    } catch {
      return { error: "OpenAI returned non-JSON", raw: content };
    }
  }
  return normalizeReport(parsedJson);
}

/* ---------- Route ---------- */
app.post("/api/analyze", async (req, res) => {
  try {
    const { imageDataUrl } = req.body || {};
    if (!imageDataUrl) return res.status(400).json({ error: "imageDataUrl is required" });

    const provider = (process.env.PROVIDER || "gemini").toLowerCase();

    let result;
    if (provider === "openai") {
      result = await analyzeWithOpenAI({ imageDataUrl });
    } else {
      result = await analyzeWithGemini({ imageDataUrl });
    }

    // If not JSON ，result {error, raw}
    if (result?.error) return res.status(200).json(result);

    res.json(result);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Backend failure", detail: String(err?.message || err) });
  }
});

const port = process.env.PORT || 8787;
// app.listen(port, '127.0.0.1', ...
app.listen(port, () => console.log(`LLM4Art backend on http://localhost:${port} (provider=${process.env.PROVIDER || "gemini"})`));
