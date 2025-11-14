module.exports = {
  apps: [
    {
      name: "llm4art-server",
      script: "server/server.js",
      cwd: ".",
      // If you use dotenv, server.js will read .env.
      // PM2 can also inject env vars directly here:
      env: {
        PORT: process.env.PORT || "8787",
        // If needed, you can put OPENAI_API_KEY here (not recommended to hardcode in repo)
        // OPENAI_API_KEY: "sk-xxxx",
        // OPENAI_MODEL: "gpt-4o-mini",
      },
      interpreter: "node",
      instances: 1,
      exec_mode: "fork",
      autorestart: true,
      max_restarts: 10,
      watch: false,
      out_file: "logs/server.out.log",
      error_file: "logs/server.err.log",
      time: true
    },
    {
      name: "llm4art-static",
      // Simple static server using Python.
      // Note: If your Python executable is not `python3`, change to `python` or an absolute path.
      script: "python3",
      args: ["-m", "http.server", "5500"],
      cwd: ".",
      interpreter: null,
      instances: 1,
      exec_mode: "fork",
      autorestart: true,
      max_restarts: 10,
      watch: false,
      out_file: "logs/static.out.log",
      error_file: "logs/static.err.log",
      time: true
    }
  ]
};
