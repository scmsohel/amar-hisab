import React, { useEffect, useState } from "react";
import {createRoot} from "react-dom/client";
import App from "./App";
import SignupPage from "./SignupPage";
import LoginPage from "./LoginPage";
import "./styles.css";

function AuthGate() {
  const [status, setStatus] = useState<"checking" | "authenticated" | "unauthenticated">("checking");
  useEffect(() => {
    fetch("/api/auth/me", { credentials: "same-origin" })
      .then(response => setStatus(response.ok ? "authenticated" : "unauthenticated"))
      .catch(() => setStatus("unauthenticated"));
  }, []);
  if (status === "checking") return <div style={{minHeight:"100vh",display:"grid",placeItems:"center",fontFamily:"sans-serif"}}>Amar Hisab লোড হচ্ছে…</div>;
  if (status === "unauthenticated") {
    if (window.location.pathname !== "/login") window.location.replace("/login");
    return <LoginPage />;
  }
  return <App />;
}

const root = document.getElementById("root")!;
const path = window.location.pathname.replace(/\/+$/, "") || "/";
createRoot(root).render(
  <React.StrictMode>
    {path === "/signup" ? <SignupPage /> : path === "/login" ? <LoginPage /> : <AuthGate />}
  </React.StrictMode>
);
