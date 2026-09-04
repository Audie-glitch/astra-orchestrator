#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 0 ]]; then
  packet="$*"
else
  packet="$(cat)"
fi

if [[ -z "${packet//[[:space:]]/}" ]]; then
  echo "Provide a non-empty orchestration packet on stdin or as arguments." >&2
  exit 64
fi

system_prompt='You are GPT-6 Astra, the orchestration controller for Codex. You plan and adjudicate only; never assign yourself implementation. Use only the supplied packet. Return a concise executable task graph, not implementation. For each node specify: id, purpose, dependencies, recommended model or agent type chosen only from the supplied callable menu, exclusive file or responsibility ownership, expected output, verification, and stop condition. Every implementation node must use GPT-5.6 Luna or DeepSeek V4 Flash and no other model. Identify nodes safe to run in parallel. Minimize the number of agents. Preserve the user scope and approval boundaries. End with an integration and final-verification node. Do not expose chain-of-thought; provide decisions and brief rationale only.

Apply this classifier only when the user did not explicitly choose an allowed implementation route. Loop construction, repeated iteration, and high-throughput mechanical work use a callable OpenCode Go agent pinned to opencode-go/deepseek-v4-flash. All other implementation prefers a callable OpenCode Go agent pinned to opencode-go-responses/gpt-5.6-luna, then opencode-go/deepseek-v4-flash. Never assign implementation to any other model, including GPT-6 Astra. Planning, research, and review use normal task fit but remain orchestration support, not implementation. GPT-6 Astra adjudication stays outside the worker graph. Prefer a callable agent_type that pins both model and provider over a raw cross-provider model string, and classify by that pin rather than the agent display name. A model merely discovered in local config is not callable. If neither allowed implementation route is callable, report the blocker; never invent or silently substitute a model or agent. After any applicable approval gate, start the answer with one short line per ready assignment in the form: Agent — Model: bounded responsibility.'

astra_model="${ASTRA_MODEL:-gpt-6-astra}"
astra_effort="${ASTRA_EFFORT:-low}"
api_base="${OPENAI_BASE_URL:-https://api.openai.com/v1}"

resolve_key() {
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    printf '%s' "$OPENAI_API_KEY"
    return 0
  fi
  if command -v openai >/dev/null 2>&1; then
    # openai CLI may already be logged in; fall through to CLI path
    return 1
  fi
  return 1
}

call_via_curl() {
  local key="$1"
  local body response status
  body="$(jq -n \
    --arg model "$astra_model" \
    --arg effort "$astra_effort" \
    --arg system "$system_prompt" \
    --arg packet "$packet" \
    '{
      model: $model,
      reasoning: {effort: $effort},
      input: [
        {role: "developer", content: $system},
        {role: "user", content: $packet}
      ]
    }')"
  response="$(mktemp)"
  set +e
  status="$(curl -sS -o "$response" -w '%{http_code}' \
    -X POST "${api_base%/}/responses" \
    -H "Authorization: Bearer ${key}" \
    -H 'Content-Type: application/json' \
    -d "$body")"
  set -e
  if [[ "$status" != "200" ]]; then
    echo "OpenAI Responses API error (HTTP ${status}):" >&2
    head -c 2000 "$response" >&2 || true
    echo >&2
    rm -f "$response"
    return 1
  fi
  # Prefer output_text; fall back to concatenating message texts
  if jq -e '.output_text' "$response" >/dev/null 2>&1; then
    jq -r '.output_text // empty' "$response"
  else
    jq -r '
      [.output[]?
        | select(.type=="message")
        | .content[]?
        | select(.type=="output_text")
        | .text] | join("\n")
    ' "$response"
  fi
  rm -f "$response"
}

call_via_openai_cli() {
  # Best-effort: openai responses create if the CLI supports it
  if openai responses create -h >/dev/null 2>&1; then
    openai responses create \
      --model "$astra_model" \
      -g "developer=${system_prompt}" \
      -g "user=${packet}" 2>/dev/null | jq -r '.output_text // .output[0].content[0].text // empty'
    return $?
  fi
  return 127
}

response=""
selected=""

if key="$(resolve_key)"; then
  if response="$(call_via_curl "$key")"; then
    selected="$astra_model"
  fi
elif command -v openai >/dev/null 2>&1; then
  if response="$(call_via_openai_cli)"; then
    selected="$astra_model (openai-cli)"
  fi
fi

if [[ -z "$selected" || -z "${response//[[:space:]]/}" ]]; then
  cat >&2 <<'ERR'
No usable GPT-6 Astra route.
Set OPENAI_API_KEY (or configure the OpenAI CLI), ensure network access to the API,
and that model gpt-6-astra is enabled on the account. This helper never stores keys.
ERR
  exit 69
fi

printf 'GPT-6 Astra speaks (%s):\n\n%s\n' "$selected" "$response"
