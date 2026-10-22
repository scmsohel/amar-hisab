import React from "react";
import {createRoot} from "react-dom/client";
import App from "./App";
import SignupPage from "./SignupPage";
import "./styles.css";

const root = document.getElementById("root")!;
const path = window.location.pathname.replace(/\/+$/, "") || "/";
createRoot(root).render(
  <React.StrictMode>
    {path === "/signup" ? <SignupPage /> : <App />}
  </React.StrictMode>
);
