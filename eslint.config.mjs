import js from "@eslint/js";
import globals from "globals";

export default [
  {
    ignores: ["node_modules/**"],
  },
  js.configs.recommended,
  {
    files: ["**/*.mjs"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: {
        ...globals.node,
        WebSocket: "readonly",
      },
    },
    rules: {
      "no-console": "off",
      "no-process-exit": "off",
    },
  },
];
