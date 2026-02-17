#!/usr/bin/env bash
# Sends a notification when Claude Code needs attention,
# but only if no one is attached to the tmux session.
#
# Supports: sns (Slack via SNS), ntfy, matrix, email (SES), callmebot, webhook
# Configure in ~/.claude/hooks/.env

set -euo pipefail

# --- Load secrets ---
ENV_FILE="$HOME/.claude/hooks/.env"

# Quick exit if nothing is configured
if [[ ! -f "$ENV_FILE" ]] && [[ -z "${CLAUDE_NOTIFY_METHOD:-}" ]]; then
  exit 0
fi

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

# --- Check if tmux session is attached ---
TMUX_SESSION="${CLAUDE_TMUX_SESSION:-claude}"

ATTACHED=$(tmux list-clients -t "$TMUX_SESSION" 2>/dev/null | wc -l || echo "0")
if [[ "$ATTACHED" -gt 0 ]]; then
  exit 0
fi

# --- Parse hook input from stdin ---
INPUT=$(cat)
MSG=$(echo "$INPUT" | jq -r '.message // "Claude needs your attention"' 2>/dev/null || echo "Claude needs your attention")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")

NOTIFICATION="[claude:${SESSION_ID:0:8}] $MSG"

# --- Send notification ---
METHOD="${CLAUDE_NOTIFY_METHOD:-sns}"

case "$METHOD" in
  sns)
    # Publishes a Slack Block Kit message to an SNS topic.
    # Requires: SNS_TOPIC_ARN, SLACK_CHANNEL_ID, AWS_REGION
    if [[ -z "${SNS_TOPIC_ARN:-}" || -z "${SLACK_CHANNEL_ID:-}" ]]; then
      exit 0
    fi
    AWS_REGION="${AWS_REGION:-sa-east-1}"

    SLACK_PAYLOAD=$(jq -nc \
      --arg channel "$SLACK_CHANNEL_ID" \
      --arg msg "$NOTIFICATION" \
      --arg session "${SESSION_ID:0:8}" \
      '{
        channel_id: $channel,
        text: ":claude-code: Claude Code — \($session)",
        blocks: [
          {
            type: "header",
            text: {
              type: "plain_text",
              text: ":claude-code: Claude Code Notification"
            }
          },
          {
            type: "section",
            fields: [
              { type: "mrkdwn", text: "*Session:*\n`\($session)`" },
              { type: "mrkdwn", text: "*Message:*\n\($msg)" }
            ]
          }
        ]
      }')

    aws sns publish \
      --topic-arn "$SNS_TOPIC_ARN" \
      --message "$SLACK_PAYLOAD" \
      --region "$AWS_REGION" \
      >/dev/null 2>&1 || true
    ;;

  ntfy)
    NTFY_TOPIC="${NTFY_TOPIC:-}"
    if [[ -z "$NTFY_TOPIC" ]]; then
      exit 0
    fi
    curl -sf -d "$NOTIFICATION" "ntfy.sh/${NTFY_TOPIC}" \
      >/dev/null 2>&1 || true
    ;;

  matrix)
    MATRIX_URL="${MATRIX_URL:-https://matrix.org}"
    if [[ -z "${MATRIX_ROOM_ID:-}" || -z "${MATRIX_TOKEN:-}" ]]; then
      exit 0
    fi
    TXN_ID="claude_$(date +%s%N)"
    curl -sf -X PUT \
      "${MATRIX_URL}/_matrix/client/v3/rooms/${MATRIX_ROOM_ID}/send/m.room.message/${TXN_ID}" \
      -H "Authorization: Bearer ${MATRIX_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"msgtype\":\"m.text\",\"body\":$(echo "$NOTIFICATION" | jq -Rs .)}" \
      >/dev/null 2>&1 || true
    ;;

  email)
    SES_FROM="${SES_FROM:-claude@yourdomain.com}"
    SES_TO="${SES_TO:-you@yourdomain.com}"
    AWS_REGION="${AWS_REGION:-sa-east-1}"
    aws ses send-email \
      --from "$SES_FROM" \
      --destination "ToAddresses=$SES_TO" \
      --message "Subject={Data='Claude Code Alert'},Body={Text={Data='$NOTIFICATION'}}" \
      --region "$AWS_REGION" \
      >/dev/null 2>&1 || true
    ;;

  callmebot)
    if [[ -z "${CALLMEBOT_PHONE:-}" || -z "${CALLMEBOT_APIKEY:-}" ]]; then
      exit 0
    fi
    ENCODED_MSG=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$NOTIFICATION'))" 2>/dev/null || echo "$NOTIFICATION")
    curl -sf "https://api.callmebot.com/whatsapp.php?phone=${CALLMEBOT_PHONE}&apikey=${CALLMEBOT_APIKEY}&text=${ENCODED_MSG}" \
      >/dev/null 2>&1 || true
    ;;

  webhook)
    WEBHOOK_URL="${WEBHOOK_URL:-}"
    if [[ -z "$WEBHOOK_URL" ]]; then
      exit 0
    fi
    curl -sf -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"text\":$(echo "$NOTIFICATION" | jq -Rs .)}" \
      >/dev/null 2>&1 || true
    ;;
esac
