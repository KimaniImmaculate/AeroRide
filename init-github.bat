@echo off
set NODE_TLS_REJECT_UNAUTHORIZED=0
set NODE_OPTIONS=--require c:\Users\immaculate.kimani\aeroride\patch.js
echo Starting Firebase GitHub integration with time/keep-alive patch...
npx -y firebase-tools@latest init hosting:github --project aeroride-665af
