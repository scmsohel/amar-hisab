import React, { useEffect, useState } from "react";
import {createRoot} from "react-dom/client";
import {Wallet,ChartNoAxesCombined,CalendarDays,ChartPie} from "lucide-react";
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
  if (status === "checking") return <main className={"ah-loading-screen"+(()=>{try{return window.localStorage.getItem("amar-hisab-dark")==="true"?" ah-loading-dark":"";}catch{return "";}})()} role="status" aria-live="polite" aria-label="Amar Hisab লোড হচ্ছে">
    <div className="ah-loading-scene" aria-hidden="true">
      <div className="ah-scene-cloud ah-scene-cloud-one"/><div className="ah-scene-cloud ah-scene-cloud-two"/>
      <div className="ah-finance-card ah-finance-card-chart"><ChartNoAxesCombined size={25}/><span/><span/><span/></div>
      <div className="ah-finance-card ah-finance-card-calendar"><CalendarDays size={23}/><i/><i/><i/><i/></div>
      <div className="ah-finance-card ah-finance-card-pie"><ChartPie size={25}/><span/></div>
      <div className="ah-loading-orbit ah-loading-orbit-outer"/><div className="ah-loading-orbit ah-loading-orbit-inner"/>
      <div className="ah-loading-wallet"><div className="ah-loading-wallet-shine"/><Wallet size={43} strokeWidth={1.8}/><span className="ah-wallet-clasp"/></div>
      <div className="ah-scene-hill ah-scene-hill-back"/><div className="ah-scene-hill ah-scene-hill-front"/>
      <div className="ah-scene-ground"/>
    </div>
    <div className="ah-loading-copy"><div className="ah-loading-wordmark"><span className="ah-wordmark-icon"><Wallet size={20}/></span><span>Amar Hisab</span></div><p>আপনার হিসাব প্রস্তুত হচ্ছে</p><div className="ah-loading-dots" aria-hidden="true"><i/><i/><i/></div></div>
  </main>;
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
