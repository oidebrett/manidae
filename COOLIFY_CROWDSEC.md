Secure Your Coolify Server & Websites with CrowdSec and Traefik


This guide shows you how to fully secure your Coolify server and all your hosted websites using CrowdSec. We'll install CrowdSec on the host ubuntu server then connect it with a firewall bouncer, and protect all traffic globally via the CrowdSec Traefik plugin.


Why This Setup As Coolify Firewall?
CrowdSec Host Agent: Protects your whole server (SSH, system-level)

Firewall-Bouncer (nftables): Automatically blocks attackers on network level

CrowdSec Bouncer Plugin for Traefik: Blocks bad IPs on HTTP/HTTPS application layer

Traefik Middleware Rule: Applies to all domains without setting labels per website

Lightweight & Efficient: Minimal resource usage, big security impact

If you want to apply CrowdSec protection only for your websites without protecting the whole server, you can follow this guide 👉 Protect Your Coolify Websites with CrowdSec Firewall


NOTE: If you’re new to this, it’s best to test it first on a development server before deploying to production.

What is CrowdSec?
CrowdSec is a community-powered, open-source intrusion prevention system (IPS). It analyzes server logs in real time, detects suspicious behavior, and automatically blocks malicious IPs — all while learning from a global network of users.


Through the CrowdSec dashboard, you can:

View attacker IPs and their origin

Monitor attack patterns (like XSS, SQLi, SSH brute force)

See risk scores and history

Share decisions across servers


Here’s a visual to help you understand how everything fits together:



Step 1: Install CrowdSec on the Host Machine:
To make your own Coolify firewall simply install CrowdSec on your coolify host server using the following command: 

curl -s https://install.crowdsec.net | sudo bash

apt install crowdsec
Then check how's it running:

sudo systemctl status crowdsec
Make sure the port 8080 is available on your host or even not used by any other containers like Traefik 

You can change the port from the file: /etc/crowdsec/config.yaml


Change the listen uri:

sudo nano /etc/crowdsec/config.yaml

From: 
	listen_uri: 127.0.0.1:8080

To:
  listen_uri: 0.0.0.0:8080
Don't forget to restart the CrowdSec service: 

sudo systemctl restart crowdsec

Step 2: Install the Firewall Bouncer (nftables):
sudo apt install crowdsec-firewall-bouncer-nftables -y
sudo systemctl enable crowdsec-firewall-bouncer-nftables --now
Check metrics:

sudo cscli metrics
Look for: cs-firewall-bouncer under Local API Bouncers Metrics.


Integrate CrowdSec community with Your Infrastructure (optional) :
Enrolling your CrowdSec agent with CrowdSec.net is completely optional. Without it, CrowdSec still works perfectly, analyzing logs locally and blocking malicious IPs using your bouncers. 

However, connecting to the global console gives you access to a powerful web dashboard, threat intelligence from the community, geolocation data, and shared blocklists. For production environments, enrollment is recommended—but for development or privacy-focused setups, staying local is just fine.


CrowdSec offers two main ways to monitor and manage your security setup:


Local dashboards via Metabase (optional Docker container)

CrowdSec Console at app.crowdsec.net for centralized visibility and management

CLI command line builtin and easy to manage.


To get started, simply signup on https://app.crowdsec.net/signup then enroll your instance by copying the generated command from your CrowdSec Console, then execute it inside your host terminal using:

sudo cscli console enroll XXXXX

You should get something similar to this:


After running the command, go back to the console and approve the enrollment to activate your dashboard view.

At this point, our Coolify Firewall CrowdSec is running — but it’s not yet analyzing Traefik logs, so it won’t make any blocking decisions yet.. to do that we will add a Remediation Component + Traefik Logs 💪

Remediation components are what CrowdSec uses to take action (like blocking bad IPs). These actions are triggered by CrowdSec’s decision engine (LAPI), based on logs it parses from your applications like Traefik.
Step 3: Get Bouncer API Key for Traefik:
sudo cscli bouncers add traefik-bouncer
Copy the key shown. You'll use it in the next step.


Step 4: Getting Traefik Ready for CrowdSec:
Let’s begin by setting up Traefik Proxy with the CrowdSec plugin. This plugin acts as the Remediation Component, enabling Traefik to interact with CrowdSec. Next, we’ll grant CrowdSec access to Traefik logs by mounting the appropriate access.log file into the Traefik container using a volume. This lets CrowdSec analyze traffic and apply real-time protection.


Create crowdsec-plugin.yaml inside Traefik
http:
  middlewares:
   crowdsec:
	 plugin:
	   crowdsec-bouncer:
		crowdsecMode: live
	  	crowdsecLapiHost: 'host.docker.internal:8080'
	  	crowdsecLapiKey: 'PASTE_YOUR_KEY_HERE'
		enabled: true

Update Traefik Docker Compose file:
  CrowdSec Traefik integration These to make crowdsec works as the middleware in front of the Traefik 

- '--entrypoints.http.http.middlewares=crowdsec@file'
- '--entrypoints.https.http.middlewares=crowdsec@file'
If your websites using cloudflare DNS dont forget to add these to Traefik:

- "--entryPoints.http.forwardedHeaders.insecure=true"
- "--entryPoints.https.forwardedHeaders.insecure=true"

Then add the plugin config:

- '--experimental.plugins.crowdsec-bouncer.modulename=github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin'
- '--experimental.plugins.crowdsec-bouncer.version=v1.2.1'

Make sure to enable the access.log for Traefik by adding this:

- '--accesslog=true'
- '--accesslog.format=json'
- '--accesslog.bufferingsize=0'
- '--accesslog.fields.headers.defaultmode=drop'
- '--accesslog.fields.headers.names.User-Agent=keep'
- '--accesslog.filepath=/traefik/access.log'
To get more details log from Traefik you will need to add this: 

- '--log.level=INFO'

Then restart Traefik container:

docker restart coolify-proxy

Last Step To Secure Coolify Server:
We need to enable parser for Traefik Logs, to make CrowdSec Traefik integration fully works and that by doing the following commands: 

cscli collections install crowdsecurity/traefik

sudo systemctl reload crowdsec
Add the Traefik logs to CrowdSec configs: 

sudo nano /etc/crowdsec/acquis.yaml
Then add the Traefik log path: 

filenames:
  - /var/log/traefik/*.log
labels:
  type: traefik
  log_type: http_access-log
The do restart for CrowdSec and Traefik: 

docker restart coolify-proxy
sudo systemctl restart crowdsec

Test To See Your Secure Coolify Server Works:
Use this to block your IP:

cscli decisions add -i 1.2.3.4 -d 10m
Try to visit any site from that IP, try to access the SSH 


If you’re only interested in protecting your websites not everything on the server, check my other guide Protect Your Coolify Websites with CrowdSec Firewall.


What about Fail2Ban? Do I still need it with CrowdSec on Coolify?

Fail2Ban is a classic tool to block brute-force SSH and similar attacks. If you’re running CrowdSec with Traefik (like we show here), CrowdSec is already handling web-related attacks. For SSH protection, you can still use Fail2Ban or let CrowdSec handle it with an SSH scenario. We’ll publish a full Coolify + Fail2Ban guide soon — stay tuned.

Final Tips & Summary

CrowdSec Traefik bouncer protects all HTTP/HTTPS traffic

Firewall bouncer protects SSH & server ports

All logs are stored in: /traefik/access.log

Use host.docker.internal to connect Traefik to CrowdSec LAPI



Result
You now have:


Global HTTP+HTTPS protection for unlimited Coolify websites

System-level protection for SSH & critical server ports

Clean & scalable setup — no need to add per-project labels

Fully extensible — ready to add CrowdSec AppSec WAF if needed

