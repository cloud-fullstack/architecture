# Chatbot Infrastructure Architecture

## Author
Aldo Grandoni

## Overview

This document describes the complete architecture of the Conversational chatbot platform: a multi-tenant system that provides virtual assistants (voice + text) embeddable into third-party websites, backed by a language-processing engine (LLM/STT/TTS), authentication, subscription management, notifications, and dataset-generation tooling for model fine-tuning.

The platform is composed of seven independent repositories, each responsible for a specific layer of the stack, orchestrated on a **k3s** cluster via Helm.

## System Architecture

```mermaid
graph TD
    subgraph "Client Website"
        W[Embeddable Widget - widget.js]
    end

    subgraph "Gateway Layer (chat-assist-connect-hub)"
        GW[Fastify Gateway]
        GW --> |REST proxy| API[/api/chat, /api/tts/]
        GW --> |WebSocket proxy| WS[/ws/chat/]
    end

    subgraph "Language Engine (backend_llm)"
        LLMR[LLM Router] --> LLMP1[Together AI - primary]
        LLMR --> LLMP2[Qwen self-hosted - fallback]
        STTR[STT Router] --> STTP1[Voxtral Mini via Together - primary]
        STTR --> STTP2[Vosk self-hosted - fallback]
        TTSR[TTS Router] --> TTSP1[Kokoro self-hosted - primary]
        TTSR --> TTSP2[Piper self-hosted - fallback IT/EN/ES/FR/DE]
        REDIS[(Redis - conversation state, rate limiting)]
    end

    subgraph "Business Services (backend_spring_kafka)"
        AUTH[Auth Service]
        SUB[Subscription Service]
        NOTIF[Notification Service]
        KAFKA[[Kafka - user.auth.events, plan.updates, auth_errors]]
        PG[(PostgreSQL)]
    end

    subgraph "Python Client (spring-client-chatbot)"
        SPC[SpringClient - HTTP/JWT wrapper]
    end

    subgraph "Dataset Generation (easy-dataset)"
        ED[Next.js App]
        ED --> |question/answer extraction| DOC[PDF/MD/DOCX Documents]
        ED --> |export| HF[Hugging Face / LLaMA Factory]
    end

    subgraph "Marketing Frontend (moonwald-s-sonic-oasis)"
        FE[React SSR - multilingual public site]
    end

    W --> GW
    GW --> LLMR
    GW --> STTR
    GW --> TTSR
    LLMR --> REDIS
    STTR --> REDIS
    SPC --> AUTH
    SPC --> SUB
    AUTH --> KAFKA
    SUB --> KAFKA
    KAFKA --> NOTIF
    AUTH --> PG
    SUB --> PG
    backend_llm -.-> |direct call for subscription/plan| SPC
    ED -.-> |fine-tuning dataset| LLMP2
```

## Component Descriptions

### 1. `chat-assist-connect-hub` — Public Gateway and Widget

Public entry layer of the platform. A **Node.js/Fastify** service that exposes:

- **Embeddable JavaScript widget** (`widget.js`, `telemaco-widget.js`): a lightweight script (~50KB) to drop into any client website. It contains no business logic — only UI rendering (chat bubble, voice button), environment detection (production/demo/staging/local), and communication with the gateway.
- **REST proxy**: routes `/api/chat`, `/api/tts`, `/api/tts/features`, `/api/v1/widget/verify` to `backend_llm`, injecting the service JWT.
- **WebSocket proxy** (`/ws/chat`): validates `widget_key` and `Origin` before completing the WebSocket upgrade, applies per-IP rate limiting, then forwards frames bidirectionally to the `backend_llm` WebSocket.
- **Security**: whitelist of valid `widget_key`s, whitelist of allowed CORS origins, in-memory per-IP rate limiting.

This component fully decouples the client website from the LLM engine: the widget never knows the internal backend URL.

### 2. `backend_llm` — Language Processing Engine

**Python/FastAPI** service that is the core of the conversational intelligence. It exposes routes for:

- **Chat/LLM**: completions based on **Together AI** (primary model, e.g. `google/gemma-4-31B-it`), with fallback to a self-hosted LLM (Qwen) when available.
- **STT (Speech-to-Text)**: language-aware fallback chain — **Voxtral Mini 3B** via Together.ai as primary, **Vosk** (self-hosted, offline, zero cost) as fallback.
- **TTS (Text-to-Speech)**: **Kokoro** (self-hosted, supports IT/EN/ES/FR) as primary, **Piper** (self-hosted, also supports DE) as fallback when Kokoro doesn't support the requested language.
- **RAG and Intent Recognition**: dedicated routers for document search and user intent recognition.
- **WebSocket chat**: real-time channel for streaming conversations.
- **WhatsApp integration**: optional sidecar consumer, enabled via feature flag.

Provider configuration (fallback chains, models, URLs, supported languages) is externalized in a `providers.properties` file, loaded at runtime by a `ProviderConfigManager` that allows switching primary/fallback providers without modifying the code.

A co-located **Redis** instance maintains conversation state and rate limiting.

### 3. `backend_spring_kafka` — Business Services (Auth, Subscriptions, Notifications)

A set of **Spring Boot** microservices that handle application logic not related to AI:

- **`auth-service`**: user authentication, JWT issuance, role and subscription plan management.
- **`subscription-service`**: management of plans (free/basic/premium/professional/enterprise) that determine which TTS/STT/LLM providers are available to the user.
- **`notification-service`**: consumer of Kafka events for sending notifications (e.g. plan changes, authentication errors).

Inter-service communication happens over **Apache Kafka**, with dedicated topics (`user.auth.events`, `plan.updates`, `auth_errors`). An abstraction layer (`MessageTransport`/`KafkaTransport`) attempts delivery via Kafka and automatically falls back to a direct REST call if the broker is unavailable, ensuring resilience.

Persistent data (users, plans, event history) is stored in **PostgreSQL**.

### 4. `spring-client-chatbot` — Python Client for Spring Services

Python library (`SpringClient`) used by `backend_llm` to communicate with `backend_spring_kafka` without duplicating HTTP authentication logic. It handles:

- Login and JWT token retrieval/validation.
- Fetching user subscription data (to determine which TTS/STT/LLM provider to route to).
- Booking, cancelling, and querying slots/appointments (booking functionality used by vertical use cases, e.g. medical practice, restaurant).

It serves as a lightweight bridge between the Python conversational engine and the Java services, avoiding direct coupling between the two technology stacks.

### 5. `easy-dataset` — Fine-Tuning Dataset Generation

Standalone **Next.js** application, used as an offline/internal tool for building training datasets for the LLM models used by the platform:

- Extracts text from documents (PDF, Markdown, DOCX, EPUB) and intelligently segments them.
- Automatically generates questions, answers, and Chain-of-Thought reasoning using configurable LLMs (OpenAI-compatible: OpenAI, Ollama, Zhipu, OpenRouter, etc.).
- Supports single-turn, multi-turn, and image-QA datasets.
- Exports in formats compatible with **LLaMA Factory** and allows direct upload to **Hugging Face Hub**.

This component is not exposed in production: it's a support tool for preparing training/evaluation data for self-hosted models (e.g. the future Qwen fallback LLM in `backend_llm`).

### 6. `k3s_engine_llm` — LLM Engine Helm Chart

Helm chart dedicated to deploying `backend_llm` on the k3s cluster. Includes:

- **Deployment** of the FastAPI service with an init-container that waits for Redis availability.
- **Redis StatefulSet** with persistence and an auto-generated password.
- **Secrets** for provider API keys (Together AI, Cartesia, WhatsApp Business API).
- **NetworkPolicy** to isolate namespace traffic.
- **Optional sidecar** for the WhatsApp consumer and `easy-dataset` integration.
- Configuration via `values.yaml` to enable/disable feature flags (WhatsApp, autoscaling, etc.).

### 7. `k3s_Conversational` — Frontend and Public Gateway Helm Chart

Helm chart that orchestrates the public-facing part of the platform (domain `Conversational.dev`):

- **Frontend Deployment**: static Nginx site serving the React build of the marketing portal.
- **Gateway Deployment**: the `chat-assist-connect-hub` service (Node/Fastify), exposed internally on port 8080.
- **Multiple Ingresses** (Traefik): one for the main site (`Conversational.dev`, `www.Conversational.dev`), one for the API gateway (`api.Conversational.dev`), one dedicated to the WebSocket (`ws.Conversational.dev/ws/chat`) with `Exact` path matching to avoid routing conflicts.
- **Traefik Middleware**: security headers (HSTS, CSP, X-Frame-Options), rate limiting, dynamic CORS whitelist for the WebSocket channel.
- **ConfigMap**: Nginx configuration and dynamic site content (hero video, multilingual translations, social links) injected from `values.yaml` without needing a Docker image rebuild for content-only updates.

### Related Project: `moonwald-s-sonic-oasis`

Public marketing site (React/Vite with Nitro SSR), served by the frontend Deployment of the `k3s_Conversational` chart. Supports dynamic content (YouTube video, translations in 5 languages) configurable via ConfigMap without an image rebuild for text/content-only changes.

## Typical Request Flow

1. The user interacts with the **widget** embedded on the client website (voice or text).
2. The widget opens a **WebSocket** connection to `ws.Conversational.dev`, routed by the Traefik Ingress to the **gateway** (`chat-assist-connect-hub`).
3. The gateway validates `widget_key` and `Origin`, applies rate limiting, then forwards the request to **`backend_llm`**.
4. If the input is voice, `backend_llm` runs **STT** (Voxtral → Vosk fallback), then passes the text to the **LLM** engine (Together AI → Qwen fallback).
5. If needed, `backend_llm` queries **`spring-client-chatbot`** to verify the user's subscription plan (via `backend_spring_kafka`/`auth-service`/`subscription-service`), determining which providers are available.
6. The text response is optionally converted to audio via **TTS** (Kokoro → Piper fallback) and sent back to the client over WebSocket.
7. Relevant events (login, plan change, errors) are published to **Kafka** and consumed by `notification-service` for sending notifications.

## Security

- **Authentication**: JWT issued by `auth-service`, verified both by the gateway (for internal services) and by `backend_llm`.
- **Widget validation**: `widget_key` and `Origin` whitelist verified before every WebSocket upgrade.
- **Rate limiting**: applied both at the gateway level (per IP) and at the Traefik Middleware level (global).
- **Secrets management**: API keys and credentials managed via Kubernetes Secrets, never hardcoded in Helm charts.
- **TLS**: TLS termination on all Ingresses via cert-manager (Let's Encrypt).
- **Provider resilience**: every external service (LLM, STT, TTS, Kafka) has a self-hosted fallback chain to ensure service continuity and limit costs.

## Deployment

Each project has its own independent build/deploy cycle:

1. **`k3s_engine_llm`**: `helm upgrade backend-llm ./k3s_engine_llm/charts/backend-llm` for the LLM/STT/TTS engine.
2. **`k3s_Conversational`**: `helm upgrade Conversational ./k3s_Conversational/charts/Conversational` for the frontend + public gateway.
3. **`backend_spring_kafka`**: Maven/Gradle build of the individual Spring Boot microservices and deploy via the charts in `backend_spring_kafka/charts/`.
4. **Content-only updates** (text, translations, video IDs) do not require a Docker rebuild: they are injected via ConfigMap and applied with a simple `helm upgrade`.
5. **Code updates** (React, Fastify, FastAPI, Spring) require rebuilding the Docker image, importing it into the k3s containerd registry, and a subsequent `helm upgrade`.

## Status

⚠️ This codebase has been developed and tested locally / on the k3s staging cluster but has **not yet been pushed to the corresponding GitHub repositories**. The remote repositories currently reflect an earlier state of the project. Synchronization is pending.
