# API Specs

This directory contains JSON specifications of the OpenAI and Anthropic API formats.
These files are used for:
- Validating proxy protocol conversions.
- Writing unit tests for request/response parsing.
- Mocking external API responses.

## Files

### OpenAI
- `openai-chat-completions.json`: The Chat Completions API (`POST /v1/chat/completions`).

### Anthropic
- `anthropic-messages.json`: The Messages API (`POST /v1/messages`), including streaming, tools, and content blocks.
- `anthropic-models.json`: The Models API (`GET /v1/models`) for listing and retrieving available models.
- `anthropic-batches.json`: The Batches API (`/v1/messages/batches`) for asynchronous batch processing.
- `anthropic-count-tokens.json`: The Count Tokens API (`POST /v1/messages/count_tokens`) for estimating input token usage.
