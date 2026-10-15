import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { ConfigError, parseConfig } from "./config";
import "./styles.css";

const root = createRoot(document.getElementById("root")!);

try {
  const config = parseConfig(import.meta.env as unknown as Record<string, string | undefined>);
  root.render(
    <StrictMode>
      <App config={config} />
    </StrictMode>,
  );
} catch (e) {
  // Fail fast and visibly on bad configuration, instead of half-working with wrong addresses.
  const message = e instanceof ConfigError ? e.message : String(e);
  root.render(
    <main>
      <h1>Configuration error</h1>
      <p className="error">{message}</p>
      <p>Copy <code>.env.example</code> to <code>.env.local</code> and fix the value.</p>
    </main>,
  );
}
