#!/bin/sh
# Seed the platform's Pangolin integration-API key (PrivateInference, manidae-cloud).
#
#   PI_PANGOLIN_KEY='<apiKeyId>.<secret>' ./components/private-inference/seed-pangolin-key.sh <pangolin-container>
#
# Runs on the host from the main stack's post_deploy, after Pangolin is up. Idempotent:
# the key row is replaced and its actions re-granted on every deploy. The key is hashed
# with Pangolin's own argon2 module and parameters (server/auth/password.ts), and is
# root (no org check) but limited to the 17 site/resource/target/domain actions the
# platform needs to publish a GPU through Newt. Pangolin ee-1.14.1, 2026-10-22.
set -eu
CONTAINER="${1:?usage: seed-pangolin-key.sh <pangolin-container>}"
: "${PI_PANGOLIN_KEY:?PI_PANGOLIN_KEY is required}"
case "$PI_PANGOLIN_KEY" in
    *.*) ;;
    *) echo "PI_PANGOLIN_KEY must be <apiKeyId>.<secret>" >&2; exit 1 ;;
esac

for _ in $(seq 1 90); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null)" = "healthy" ] && break
    sleep 2
done

docker exec -e PI_PANGOLIN_KEY "$CONTAINER" node -e '
const D = require("better-sqlite3");
const { hash } = require("@node-rs/argon2");
const [id, secret] = process.env.PI_PANGOLIN_KEY.split(".");
const ACTIONS = ["listSites", "getSite", "createSite", "updateSite", "deleteSite",
  "listOrgDomains", "getDomain", "createResource", "getResource", "updateResource",
  "deleteResource", "listResources", "createTarget", "getTarget", "updateTarget",
  "deleteTarget", "listTargets"];
(async () => {
  const h = await hash(secret, { memoryCost: 19456, timeCost: 2, outputLen: 32, parallelism: 1 });
  const db = new D("/app/config/db/db.sqlite");
  db.transaction(() => {
    db.prepare("DELETE FROM apiKeyActions WHERE apiKeyId = ?").run(id);
    db.prepare("DELETE FROM apiKeys WHERE apiKeyId = ?").run(id);
    db.prepare("INSERT INTO apiKeys (apiKeyId, name, apiKeyHash, lastChars, dateCreated, isRoot) VALUES (?, ?, ?, ?, ?, 1)")
      .run(id, "manidae-cloud (PrivateInference)", h, secret.slice(-4), new Date().toISOString());
    const grant = db.prepare("INSERT INTO apiKeyActions (apiKeyId, actionId) VALUES (?, ?)");
    for (const a of ACTIONS) grant.run(id, a);
  })();
  console.log("pangolin integration key " + id + " seeded with " + ACTIONS.length + " actions");
})().catch((e) => { console.error(e); process.exit(1); });
'
