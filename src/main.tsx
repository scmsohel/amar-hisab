import React from "react";
import {createRoot} from "react-dom/client";
import App from "./App";
import SignupPage from "./SignupPage";
import LoginPage from "./LoginPage";
import "./styles.css";

const root = document.getElementById("root")!;
const path = window.location.pathname.replace(/\/+$/, "") || "/";
createRoot(root).render(
  <React.StrictMode>
    {path === "/signup" ? <SignupPage /> : path === "/login" ? <LoginPage /> : <App />}
  </React.StrictMode>
);
