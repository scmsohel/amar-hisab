import { useState } from "react";
import type { ReactNode } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowRight, Check, CheckCircle2, Eye, EyeOff, KeyRound, Leaf, LockKeyhole, Mail, Moon, Smartphone, Sun, UserRound, WalletCards } from "lucide-react";
import "./signup.css";

export default function SignupPage() {
  const [step, setStep] = useState(0);
  const [dark, setDark] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [form, setForm] = useState({ invite: "", name: "", email: "", mobile: "", password: "", confirm: "" });
  const [error, setError] = useState("");
  const [complete, setComplete] = useState(false);
  const update = (key: keyof typeof form, value: string) => setForm(old => ({ ...old, [key]: value }));
  const next = () => {
    setError("");
    if (step === 0 && !form.invite.trim()) return setError("আপনার Admin-এর দেওয়া invitation code লিখুন।");
    if (step === 1 && (!form.name.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email) || !form.mobile.trim())) return setError("নাম, সঠিক Email এবং Mobile নম্বর দিন।");
    if (step === 2 && (form.password.length < 8 || form.password !== form.confirm)) return setError("Password কমপক্ষে ৮ অক্ষরের হতে হবে এবং দুইটি মিলতে হবে।");
    if (step < 2) setStep(step + 1);
    else setComplete(true);
  };
  const input = (label: string, key: keyof typeof form, placeholder: string, Icon: typeof KeyRound, type = "text", right?: ReactNode) => (
    <label className="signup-field">{label}<span className="signup-input"><Icon size={18}/><input required aria-label={label} type={type} value={form[key]} onChange={e => update(key, e.target.value)} placeholder={placeholder}/>{right}</span></label>
  );
  return <main className={"signup-page" + (dark ? " signup-dark" : "")}>
    <section className="signup-story">
      <div className="signup-brand"><span className="signup-brand-icon"><WalletCards size={28}/><Leaf size={14}/></span><div><strong>Amar <em>Hisab</em></strong><small>Your Personal Finance Companion</small></div></div>
      <div className="signup-story-copy"><span className="signup-kicker">YOUR MONEY, YOUR WAY</span><h1>Track Today.<br/>Build a Better<br/><em>Tomorrow.</em></h1><p>আপনার আয়, ব্যয় ও সঞ্চয়ের হিসাব রাখুন—এক জায়গায়, সহজে ও নিরাপদে।</p><div className="signup-benefits"><span><CheckCircle2/> সব হিসাব গুছিয়ে রাখুন</span><span><CheckCircle2/> আপনার তথ্যের গোপনীয়তা</span><span><CheckCircle2/> Web ও Mobile-এ ব্যবহার</span></div></div>
      <div className="signup-art" aria-hidden="true"><div className="signup-art-glow"/><div className="signup-mini-chart"><div className="signup-chart-head"><span/><span/><span/></div><div className="signup-chart-bars"><i/><i/><i/><i/><i/><i/></div><div className="signup-chart-line"/></div><div className="signup-art-leaf leaf-a"/><div className="signup-art-leaf leaf-b"/></div>
      <small className="signup-story-foot">A clearer picture of your finances starts here.</small>
    </section>
    <section className="signup-form-wrap">
      <motion.div className="signup-theme-toggle" whileTap={{scale:.9}}><button type="button" aria-label="থিম পরিবর্তন" onClick={()=>setDark(v=>!v)}>{dark?<Sun size={17}/>:<Moon size={17}/>}</button></motion.div>
      <AnimatePresence mode="wait">
      {complete ? <motion.div key="complete" className="signup-card signup-success" initial={{opacity:0,y:16}} animate={{opacity:1,y:0}} exit={{opacity:0,y:-10}}><motion.span className="signup-success-icon" initial={{scale:0,rotate:-25}} animate={{scale:1,rotate:0}} transition={{type:"spring",delay:.12}}><Check size={38}/></motion.span><h2>দারুণ!</h2><p>Signup form preview সম্পন্ন হয়েছে।</p><small>বাস্তব account তৈরি করতে invitation validation ও backend authentication সংযুক্ত করতে হবে।</small><button className="signup-primary signup-success-button" onClick={()=>{setComplete(false);setStep(0)}}>আবার দেখুন <ArrowRight size={17}/></button><p className="signup-privacy"><LockKeyhole size={13}/> আপনার তথ্য সুরক্ষিত রাখতে নিরাপদ authentication প্রয়োজন</p></motion.div>
      : <motion.div key={step} className="signup-card" initial={{opacity:0,x:18}} animate={{opacity:1,x:0}} exit={{opacity:0,x:-18}} transition={{duration:.22,ease:"easeOut"}}>
        <div className="signup-card-brand"><span className="signup-card-logo"><WalletCards size={24}/><Leaf size={12}/></span><strong>Amar <em>Hisab</em></strong></div>
        <h2>আপনার অ্যাকাউন্ট তৈরি করুন</h2><p className="signup-subtitle">Amar Hisab-এ যোগ দিতে Admin-এর invitation ব্যবহার করুন</p>
        <div className="signup-steps">{["Invitation","Details","Security"].map((label,i)=><div className={"signup-step"+(i===step?" active":i<step?" done":"")} key={label}><span>{i<step?<Check size={15}/>:i+1}</span><small>{label}</small></div>)}</div>
        <form onSubmit={e=>{e.preventDefault();next()}}>
          {step===0 && <div className="signup-fields">{input("Invitation Code *","invite","আপনার invitation code",KeyRound)}<div className="signup-info"><span>i</span><p>শুধুমাত্র Admin-এর দেওয়া বৈধ invitation code দিয়ে account তৈরি করা যাবে।</p></div></div>}
          {step===1 && <div className="signup-fields">{input("পূর্ণ নাম *","name","আপনার নাম",UserRound)}{input("Email Address *","email","you@example.com",Mail,"email")}{input("Mobile Number *","mobile","+880 1XXXXXXXXX",Smartphone,"tel")}</div>}
          {step===2 && <div className="signup-fields">{input("Password *","password","কমপক্ষে ৮ অক্ষর",LockKeyhole,showPassword?"text":"password",<button type="button" className="signup-eye" onClick={()=>setShowPassword(v=>!v)} aria-label="Password দেখুন">{showPassword?<EyeOff size={17}/>:<Eye size={17}/>}</button>)}{input("Confirm Password *","confirm","আবার password লিখুন",LockKeyhole,showConfirm?"text":"password",<button type="button" className="signup-eye" onClick={()=>setShowConfirm(v=>!v)} aria-label="Confirm password দেখুন">{showConfirm?<EyeOff size={17}/>:<Eye size={17}/>}</button>)}<p className="signup-password-hint">Password কমপক্ষে ৮ অক্ষরের রাখুন।</p></div>}
          {error && <motion.p className="signup-error" initial={{opacity:0,y:-4}} animate={{opacity:1,y:0}}>{error}</motion.p>}
          <div className="signup-actions">{step>0&&<button type="button" className="signup-back" onClick={()=>{setError("");setStep(s=>s-1)}}>পেছনে</button>}<motion.button type="submit" className="signup-primary" whileHover={{y:-2}} whileTap={{scale:.98}}>{step===2?"Account তৈরি করুন":"এগিয়ে যান"} <ArrowRight size={17}/></motion.button></div>
        </form>
        <p className="signup-login">ইতিমধ্যে account আছে? <a href="/login">Login করুন</a></p>
        <p className="signup-privacy"><LockKeyhole size={13}/> আপনার তথ্য সুরক্ষিত রাখতে নিরাপদ authentication প্রয়োজন</p>
      </motion.div>}
      </AnimatePresence>
    </section>
  </main>;
}
