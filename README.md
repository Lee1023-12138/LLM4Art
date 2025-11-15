# LLM4Art
LLM4Art — Direct LLM (Gemini / OpenAI)

A single-page app + Node backend that analyzes an uploaded artwork image and returns a structured art appreciation sheet (Visual Analysis, Genre/Style, Color, Line & Perspective, Shape & Form, Artifact Type, Historical Context, Cultural Significance) and basic metadata (Title/Artist/Year/Medium/Region).

Run Locally
1) Prerequisites

Node.js ≥ 18 and npm ≥ 9

(Optional) Python 3 (used by the script to serve the static page)

2) Install
cd App
npm install

3) Configure .env

Create `App/.env` (or copy from `.env.example`) and fill the keys:

```bash
# Select provider: gemini | openai
PROVIDER=gemini

# Backend port
PORT=8787

# --- Gemini ---
GOOGLE_API_KEY=YOUR_GOOGLE_API_KEY_HERE
GOOGLE_MODEL=model_name

# --- OpenAI ---
OPENAI_API_KEY=YOUR_OPENAI_API_KEY_HERE
OPENAI_MODEL=model_name
```

To switch providers, change PROVIDER and set the matching API key/model.

4) Start
cd App
chmod +x start.sh stop.sh        # first time only
./start.sh


Frontend: http://localhost:5500/index.html

Backend health: http://localhost:8787/api/health

Stop / clean up

./stop.sh


Customize ports (optional)

PORT=8080 FRONTEND_PORT=8081 ./start.sh


If you’re on a remote server (e.g., VS Code Remote-SSH), forward ports 5500 and 8787 to your local machine, then open the URLs above in your local browser.

Notes

The image is resized in the browser and sent as a dataURL to the backend.

Keep your real .env out of version control; commit .env.example instead.

If a port is in use, the script attempts to clean it. You can also override ports via env vars as shown above.# LLM4Art

