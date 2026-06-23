@echo off
set NODE_TLS_REJECT_UNAUTHORIZED=0
set NODE_OPTIONS=--require c:\Users\immaculate.kimani\aeroride\patch.js
echo Running firebase login --reauth with time/keep-alive patch...
npx -y firebase-tools@latest login --reauth
