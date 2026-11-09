# Using Tate's local LLM

Works only on Tate's home Wi-Fi. OpenAI-compatible API.

- Base URL: `http://192.168.50.66:8080/v1`
- API key: the `sk-bf-...` key Tate gave you
- Model: `sgl/qwen38-27b-tp` (list models: `GET /v1/models`)
- Limits: 20 requests/min, 500k tokens/day. Context is about 36k tokens.

```bash
curl http://192.168.50.66:8080/v1/chat/completions \
  -H "Authorization: Bearer sk-bf-YOURKEY" -H "Content-Type: application/json" \
  -d '{"model":"sgl/qwen38-27b-tp","messages":[{"role":"user","content":"Hello"}]}'
```

Python (`pip install openai`):
```python
from openai import OpenAI
c = OpenAI(base_url="http://192.168.50.66:8080/v1", api_key="sk-bf-YOURKEY")
print(c.chat.completions.create(model="sgl/qwen38-27b-tp",
      messages=[{"role": "user", "content": "Hello"}]).choices[0].message.content)
```
Thinking is off by default. To turn it on, add `"chat_template_kwargs": {"enable_thinking": true}`
(Python: `extra_body={...}`).
