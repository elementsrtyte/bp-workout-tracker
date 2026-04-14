import { config as loadEnv } from "dotenv";

loadEnv();
loadEnv({ path: ".env.local", override: true });

import { createApp } from "./app.js";

const app = createApp();
const port = Number(process.env.PORT ?? "8787");

app.listen(port, "0.0.0.0", () => {
  console.log(`bp-workout-api listening on http://127.0.0.1:${port} (GET /v1 for route map)`);
});
