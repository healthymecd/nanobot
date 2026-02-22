FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# system + node + persistent tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl ca-certificates gnupg git tmux gh nano && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    pip install --no-cache-dir yt-dlp && \
    npm install -g @steipete/summarize && \
    rm -rf /var/lib/apt/lists/*

# clone
WORKDIR /opt/src
RUN git clone https://github.com/HKUDS/nanobot.git .

# build bridge once
WORKDIR /opt/src/bridge
RUN npm install && npm run build

# install python
WORKDIR /opt/src
RUN uv pip install --system --no-cache .

# vendor bridge into site-packages
RUN python - <<'PY'
import nanobot, pathlib, shutil
pkg = pathlib.Path(nanobot.__file__).parent
dst = pkg / "bridge"
src = pathlib.Path("/opt/src/bridge")
if dst.exists():
    shutil.rmtree(dst)
shutil.copytree(src, dst)
PY

# runtime
VOLUME /root/.nanobot

ENTRYPOINT ["sh", "-c", "\
if [ ! -f /root/.nanobot/bridge/dist/index.js ]; then \
  rm -rf /root/.nanobot/bridge; \
  mkdir -p /root/.nanobot; \
  cp -a /usr/local/lib/python3.12/site-packages/nanobot/bridge /root/.nanobot/bridge; \
fi; \
# runtime env for summarize (depends on mounted config.json) \
export OPENAI_BASE_URL='https://openrouter.ai/api/v1'; \
export OPENROUTER_API_KEY=$(grep -o '\"OPENROUTER_API_KEY\":\"[^\"]*\"' /root/.nanobot/config.json 2>/dev/null | cut -d'\"' -f4); \
export SUMMARIZE_MODEL='openai/deepseek/deepseek-r1-0528:free'; \
# idempotent tmux monitor bootstrap \
mkdir -p /root/.nanobot/workspace/logs; \
touch /root/.nanobot/workspace/logs/agent-activity.log; \
if ! tmux has-session -t agent-monitor 2>/dev/null; then \
  tmux new-session -d -s agent-monitor 'tail -f /root/.nanobot/workspace/logs/agent-activity.log'; \
  echo \"[$(date '+%Y-%m-%d %H:%M:%S')] [SYSTEM] Agent monitor session started (container restart)\" >> /root/.nanobot/workspace/logs/agent-activity.log; \
fi; \
exec nanobot \"$@\" \
", "--"]

CMD ["status"]
