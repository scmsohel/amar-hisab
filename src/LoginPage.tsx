import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowRight, Eye, EyeOff, Leaf, LockKeyhole, Mail, Moon, Smartphone, Sun, WalletCards } from "lucide-react";
import "./signup.css";
import "./login.css";

export default function LoginPage() {
  const [dark, setDark] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [recovery, setRecovery] = useState(false);
  const [sent, setSent] = useState(false);
  const [identity, setIdentity] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");

  const submitLogin = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError("");
    if (!identity.trim() || !password) {
      setError("Email/Mobile এবং Password লিখুন।");
      return;
    }
    setError("এটি Login UI preview—বাস্তব authentication এখনো সংযুক্ত করা হয়নি।");
  };

  const submitRecovery = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError("");
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(identity.trim())) {
      setError("Password recovery-এর জন্য সঠিক Email address দিন।");
      return;
    }
    setSent(true);
  };

  return (
    <main className={"signup-page login-page" + (dark ? " signup-dark" : "")}>
      <section className="signup-story">
        <div className="signup-brand">
          <span className="signup-brand-icon"><WalletCards size={28}/><Leaf size={14}/></span>
          <div><strong>Amar <em>Hisab</em></strong><small>Your Personal Finance Companion</small></div>
        </div>
        <div className="signup-story-copy">
          <span className="signup-kicker">WELCOME BACK</span>
          <h1>Your finances.<br/>All in one place.<br/><em>Every day.</em></h1>
          <p>আপনার আয়, ব্যয় ও সঞ্চয়ের হিসাব—আবার শুরু হোক এক জায়গা থেকে।</p>
          <div className="signup-benefits">
            <span><LockKeyhole/> নিরাপদে আপনার হিসাব</span>
            <span><WalletCards/> সব Wallet একসঙ্গে</span>
            <span><ArrowRight/> সহজ ও দ্রুত access</span>
          </div>
        </div>
        <div className="signup-art" aria-hidden="true">
          <div className="signup-art-glow"/>
          <div className="signup-mini-chart"><div className="signup-chart-head"><span/><span/><span/></div><div className="signup-chart-bars"><i/><i/><i/><i/><i/><i/></div><div className="signup-chart-line"/></div>
          <div className="signup-art-leaf leaf-a"/><div className="signup-art-leaf leaf-b"/>
        </div>
        <small className="signup-story-foot">A clearer picture of your finances starts here.</small>
      </section>
      <section className="signup-form-wrap login-form-wrap">
        <motion.div className="signup-theme-toggle" whileTap={{scale:.9}}>
          <button type="button" aria-label="থিম পরিবর্তন" onClick={()=>setDark(v=>!v)}>{dark?<Sun size={17}/>:<Moon size={17}/>}</button>
        </motion.div>
        <AnimatePresence mode="wait">
          {sent ? (
            <motion.div key="sent" className="signup-card login-card login-message" initial={{opacity:0,y:14}} animate={{opacity:1,y:0}} exit={{opacity:0,y:-10}}>
              <span className="login-message-icon"><Mail size={30}/></span>
              <h2>Email recovery preview</h2>
              <p>আপনার Email-এ OTP পাঠানোর ধাপটি UI preview-তে দেখানো হয়েছে। বাস্তবে OTP পাঠাতে backend ও email service যুক্ত করতে হবে।</p>
              <button className="signup-primary login-main-button" onClick={()=>{setSent(false);setRecovery(false);setError("");setIdentity("");}}>Login-এ ফিরে যান <ArrowRight size={17}/></button>
            </motion.div>
          ) : (
            <motion.div key={recovery?"recovery":"login"} className="signup-card login-card" initial={{opacity:0,x:16}} animate={{opacity:1,x:0}} exit={{opacity:0,x:-12}} transition={{duration:.22,ease:"easeOut"}}>
              <div className="signup-card-brand"><span className="signup-card-logo"><WalletCards size={24}/><Leaf size={12}/></span><strong>Amar <em>Hisab</em></strong></div>
              <h2>{recovery ? "Password reset করুন" : "আবার স্বাগতম!"}</h2>
              <p className="signup-subtitle">{recovery ? "আপনার account-এর Email দিয়ে OTP recovery শুরু করুন" : "আপনার account-এ Login করতে তথ্য দিন"}</p>
              <form onSubmit={recovery?submitRecovery:submitLogin} className="login-fields">
                <label className="signup-field">{recovery ? "Email Address" : "Email অথবা Mobile Number"}<span className="signup-input">{recovery?<Mail size={18}/>:<Smartphone size={18}/>}<input autoComplete="username" aria-label={recovery?"Email Address":"Email অথবা Mobile Number"} value={identity} onChange={e=>setIdentity(e.target.value)} placeholder={recovery?"you@example.com":"Email বা +880 1XXXXXXXXX"} type={recovery?"email":"text"}/></span></label>
                {!recovery && <label className="signup-field">Password<span className="signup-input"><LockKeyhole size={18}/><input autoComplete="current-password" aria-label="Password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="আপনার Password" type={showPassword?"text":"password"}/><button type="button" className="signup-eye" onClick={()=>setShowPassword(v=>!v)} aria-label="Password দেখুন">{showPassword?<EyeOff size={17}/>:<Eye size={17}/>}</button></span></label>}
                {!recovery && <div className="login-forgot"><button type="button" onClick={()=>{setRecovery(true);setError("");}}>Password ভুলে গেছেন?</button></div>}
                {error && <motion.p className="signup-error" initial={{opacity:0,y:-4}} animate={{opacity:1,y:0}}>{error}</motion.p>}
                <motion.button type="submit" className="signup-primary login-main-button" whileHover={{y:-2}} whileTap={{scale:.98}}>{recovery?"Email OTP পাঠানোর ধাপ দেখুন":"Login করুন"} <ArrowRight size={17}/></motion.button>
              </form>
              {recovery && <button type="button" className="login-back" onClick={()=>{setRecovery(false);setError("");}}>Login-এ ফিরে যান</button>}
              <p className="signup-login">নতুন account প্রয়োজন? <a href="/signup">Signup করুন</a></p>
              <p className="signup-privacy"><LockKeyhole size={13}/> নিরাপদ authentication প্রয়োজন</p>
            </motion.div>
          )}
        </AnimatePresence>
      </section>
    </main>
  );
}
