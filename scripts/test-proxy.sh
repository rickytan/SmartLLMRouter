#!/bin/bash
# Test SmartLLMRouter proxy with deepseek-v4-flash

PROXY="http://localhost:1897"

echo "=== 1. Health check: GET /v1/models ==="
curl -s "$PROXY/v1/models" -H "Authorization: Bearer test" | python3 -m json.tool 2>/dev/null | head -20
echo ""

echo "=== 2. Chat completion (OpenAI protocol) ==="
curl -s "$PROXY/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test" \
  -d '{
    "model": "deepseek-v4-flash",
    "max_tokens": 20,
    "messages": [{"role": "user", "content": "1+1=?"}]
  }' | python3 -m json.tool 2>/dev/null
echo ""

echo "=== 3. Streaming test ==="
curl -sN "$PROXY/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test" \
  -d '{
    "model": "deepseek-v4-flash",
    "max_tokens": 30,
    "stream": true,
    "messages": [{"role": "user", "content": "say hello in 3 words"}]
  }' 2>&1 | head -30
echo ""
echo "=== Done ==="
