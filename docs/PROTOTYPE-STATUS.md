# Prototype status

This branch contains the first front-end prototype for Amar Hisab, following the Bengali finance dashboard direction supplied by the owner.

## Included
- React + TypeScript + Vite scaffold
- Responsive dashboard shell, navigation and summary cards
- Income/expense trend chart and expense-category breakdown
- Demo transaction search/type filter and add-income/expense modal
- Light/dark mode and motion micro-interactions
- Reduced-motion CSS preference

## Not implemented yet
- Backend/API/PostgreSQL
- Authentication, invitation-only registration, email verification or password reset
- Persistent transactions (demo additions are in-memory only)
- Real transfer accounting, CRUD for wallets/categories/budgets/bills/loans/reports
- Real export, notifications, complete pagination, production tests

All financial figures are sample values. Do not use this prototype for real financial records. Next: compare in a browser with the supplied reference, refine the UI, then implement API/database and tests before production deployment.