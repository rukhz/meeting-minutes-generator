============================================
  HOW TO MAKE BOT RECORDING WORK
============================================

ON YOUR PC (where the app connects to):

1. Open this folder in File Explorer:
   Smartmeetingminutesgeneratojitsimeet\server

2. Double-click:  RUN_BOT_SERVER_EVERYTHING.bat

   - It will show "Your PC IP" and a URL like http://192.168.1.5:3000
   - It will run npm install if needed
   - It will try to open Windows Firewall for port 3000
   - It will start the bot server (keep the window open)

3. On your phone (same Wi-Fi as PC):
   - Open the Smart Meeting Minutes app
   - Turn ON "Bot recording"
   - In "Server URL" paste the URL from the PC window (e.g. http://192.168.1.5:3000)
   - Tap Test → should say "Server reachable"

4. If Test still fails:
   - Right-click RUN_BOT_SERVER_EVERYTHING.bat → Run as administrator
   - Or run ADD_FIREWALL_RULE.ps1 as Administrator (once)

============================================
