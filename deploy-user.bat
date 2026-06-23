@echo off
set NODE_TLS_REJECT_UNAUTHORIZED=0
set NODE_OPTIONS=--require c:\Users\immaculate.kimani\aeroride\patch.js
echo [1/1] Running firebase deploy (hosting + functions) using your user account...
npx -y firebase-tools@latest deploy --only hosting,functions --project aeroride-665af --force
